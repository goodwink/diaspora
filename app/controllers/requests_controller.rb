#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require File.join(Rails.root, 'lib/em-webfinger')

class RequestsController < ApplicationController
  before_filter :authenticate_user!
  include RequestsHelper

  respond_to :html

  def destroy
    if params[:accept]
      if params[:aspect_id]
        @friend = current_user.accept_and_respond( params[:id], params[:aspect_id])
        flash[:notice] = I18n.t 'requests.destroy.success'
        respond_with :location => current_user.aspect_by_id(params[:aspect_id])
      else
        flash[:error] = I18n.t 'requests.destroy.error'
        respond_with :location => requests_url
      end
    else
      current_user.ignore_friend_request params[:id]
      flash[:notice] = I18n.t 'requests.destroy.ignore'
      respond_with :location => requests_url
    end
  end

  def new
    @request = Request.new
  end

  def create
    aspect = current_user.aspect_by_id(params[:request][:aspect_id])
    account = params[:request][:destination_url].strip  
    
    #EM::next_tick { 
      finger = EMWebfinger.new(account)
      

      do_request = Proc.new{ |person|
        rel_hash = {:friend => person}
        Rails.logger.debug("Sending request: #{rel_hash}")

        begin
          @request = current_user.send_friend_request_to(rel_hash[:friend], aspect)
          
        rescue Exception => e
          Rails.logger.debug("error: #{e.message}")
          #raise e unless e.message.include? "already"
          #flash[:notice] = I18n.t 'requests.create.already_friends', :destination_url => params[:request][:destination_url]
        end
    }

    p = Person.by_account_identifier(account)
    if p 
      do_request.call(person)
      flash[:notice] = "we sent a request to #{person.real_name}"
    else
      finger = EMWebfinger.new(account)
      finger.on_person do_request
      finger.fetch
      flash[:notice] = "we tried our best to send a message to #{account}"
    end

    redirect_to aspects_manage_path

  end

end
