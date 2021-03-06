#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require 'spec_helper'
require File.join(Rails.root, 'lib/diaspora/exporter')
require File.join(Rails.root, 'lib/diaspora/importer')

describe Diaspora::Importer do

  before(:each) do
    # Five users on pod
    @user1 = Factory(:user)
    @user2 = Factory(:user)
    @user3 = Factory(:user)
    @user4 = Factory(:user)
    @user5 = Factory(:user)

    # Two external people referenced on pod
    @person1 = Factory(:person)
    @person2 = Factory(:person)

    # User1 has four aspects(1-4), each following user has one aspect
    @aspect1 = @user1.aspect(:name => "Dudes") 
    @aspect2 = @user1.aspect(:name => "Girls")
    @aspect3 = @user1.aspect(:name => "Bros")
    @aspect4 = @user1.aspect(:name => "People")
    @aspect5 = @user2.aspect(:name => "Abe Lincolns")
    @aspect6 = @user3.aspect(:name => "Cats")
    @aspect7 = @user4.aspect(:name => "Dogs")
    @aspect8 = @user5.aspect(:name => "Hamsters")
    @aspect9 = @user5.aspect(:name => "Gophers")

    @aspect10 = @user1.aspect(:name => "Work") 
    @aspect11 = @user1.aspect(:name => "Family")

    # User1 posts one status messages to aspects (1-4), two other users post message to one aspect
    @status_message1 = @user1.post(:status_message, :message => "One", :public => false, :to => @aspect1.id)
    @status_message2 = @user1.post(:status_message, :message => "Two", :public => false, :to => @aspect2.id)
    @status_message3 = @user1.post(:status_message, :message => "Three", :public => false, :to => @aspect3.id)
    @status_message4 = @user1.post(:status_message, :message => "Four", :public => false, :to => @aspect4.id)
    @status_message5 = @user2.post(:status_message, :message => "Five", :public => false, :to => @aspect5.id)
    @status_message6 = @user3.post(:status_message, :message => "Six", :public => false, :to => @aspect6.id)
    @status_message7 = @user5.post(:status_message, :message => "Seven", :public => false, :to => @aspect9.id)

    @aspect1.posts << @status_message1
    @aspect2.posts << @status_message2
    @aspect3.posts << @status_message3
    @aspect4.posts << @status_message4

    # Friend users with user1
    friend_users( @user1, @aspect1, @user2, @aspect5 )
    friend_users( @user1, @aspect2, @user3, @aspect6 )
    friend_users( @user1, @aspect3, @user4, @aspect7 )
    friend_users( @user1, @aspect4, @user5, @aspect8 )

    # Friend users 4 and 5
    friend_users( @user5, @aspect9, @user4, @aspect7 )

    # Generate status messages and receive for user1
    @user2.receive @status_message1.to_diaspora_xml, @user1.person
    @user3.receive @status_message2.to_diaspora_xml, @user1.person
    @user4.receive @status_message3.to_diaspora_xml, @user1.person
    @user5.receive @status_message4.to_diaspora_xml, @user1.person
    @user1.receive @status_message5.to_diaspora_xml, @user2.person
    @user1.receive @status_message6.to_diaspora_xml, @user3.person

    # Generate status message and recieve between user4 and user5
    @user4.receive @status_message7.to_diaspora_xml, @user5.person
  end

  it 'should gut check this test' do 
    
    @user1.friends.count.should be 4

    @user1.friends.should include @user2.person
    @user1.friends.should include @user3.person
    @user1.friends.should include @user4.person
    @user1.friends.should include @user5.person
    
    # User is generated with two pre-populated aspects
    @user1.aspects.count.should be 6
    @user1.aspects.find_by_name("Dudes").people.should include @user2.person
    @user1.aspects.find_by_name("Dudes").posts.should include @status_message5
    
    @user1.raw_visible_posts.count.should be 6
    @user1.raw_visible_posts.find_all_by_person_id(@user1.person.id).count.should be 4
    @user1.raw_visible_posts.find_all_by_person_id(@user1.person.id).should_not include @status_message7
  end

  context 'parsing a user' do

    before(:each) do
      # Generate exported XML for user1
      exporter = Diaspora::Exporter.new(Diaspora::Exporters::XML)
      @user1.aspects.reload
      @xml = exporter.execute(@user1)

      @old_user = @user1

      # Remove user1 from the server
      @user1.aspects.each( &:delete )
      @user1.raw_visible_posts.find_all_by_person_id(@user1.person.id).each( &:delete )
      @user1.delete

      @importer = Diaspora::Importer.new(Diaspora::Parsers::XML)
      @doc = Nokogiri::XML::parse(@xml)
    end

    describe '#parse_user_and_person' do
      before(:each) do
        @user, @person = @importer.parse_user_and_person(@doc)
      end

      it 'should set username' do
        @user.username.should == @old_user.username
      end

      it 'should set private key' do
        @user.serialized_private_key.should_not be nil
        @user.serialized_private_key.should == @old_user.serialized_private_key
      end

    end
    
    describe '#parse_aspects' do
      let(:aspects) { @importer.parse_aspects(@doc) }

      it 'should return valid aspects' do 
        aspects.all?(&:valid?).should be true
      end

      it 'should return an array' do
        aspects.count.should == 6
      end

      it 'should should have post ids' do
        aspects.any?{|x| x.post_ids.count > 0}.should be true
      end

      it 'should have person ids' do
        aspects.any?{|x| x.person_ids.count > 0}.should be true
      end
    end

    describe '#parse_people' do
      let(:people) { @importer.parse_people(@doc) }

      it 'should return an array' do
        people.count.should == 4 
      end
    end

    describe '#parse_posts' do
      let(:posts) { @importer.parse_posts(@doc) }

      it 'should return an array' do
        posts.count.should == 4
      end

      it 'should return vaild posts' do         
        posts.all?(&:valid?).should be true
      end
    end

  end

  describe 'importing a user' do

    context '#execute' do
      before(:each) do
        # Generate exported XML for user1
        exporter = Diaspora::Exporter.new(Diaspora::Exporters::XML)
        @xml = exporter.execute(@user1)

        # Remove user1 from the server
        @user1.aspects.each( &:delete )
        @user1.raw_visible_posts.find_all_by_person_id(@user1.person.id).each( &:delete )
        @user1.delete

        @importer = Diaspora::Importer.new(Diaspora::Parsers::XML)
      end

      it 'should import' do
        pending "there is some weirdness with diaspora handle we need to look into... and this test is terrible"
        User.delete_all
        Person.delete_all
        Post.delete_all
        StatusMessage.delete_all
        Aspect.delete_all

        User.count.should == 0
        Person.count.should == 0
        
        @importer.execute(@xml,
                          :email => "bob@bob.com",
                          :password => "bobbybob",
                          :password => "bobbybob",
                          :diaspora_handle => "bob@diaspora.com")
        
        User.count.should == 1
        n = User.first
        Post.count.should == 4 
        n.aspects.count.should  == 6
        Person.count.should be == 5 

        User.first.person.diaspora_handle.should == User.first.diaspora_handle
     

        Person.find_by_id( @user1.person.id ).nil?.should == false
        Person.find_by_id( @user2.person.id ).nil?.should == false

        n.aspects.count.should == 6
 
        people_count = 0
        n.aspects.each{|x| people_count += x.people.count }
        people_count.should == 4

        post_count = 0
        n.aspects.reload
        n.aspects.each{ |x| post_count += x.post_ids.count }
        post_count.should == 4
        
        n.friends.count.should be 4
      end

      

    end

  end

end

