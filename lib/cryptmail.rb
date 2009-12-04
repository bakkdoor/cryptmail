########################################################################
# This file is part of cryptmail.
#
# cryptmail is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# cryptmail is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with cryptmail. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

# -*- coding: utf-8 -*-

require "rubygems"
require "tmail"
require "pp"
require "yaml"
require "gpgme"

require "utils"
require "crypt_debug"

module Cryptmail  
  def self.load_settings(config_file)
    @@settings_yaml = YAML::load_file(config_file) 
  end
  
  def self.settings
    @@settings_yaml
  end

  def self.setup
    if settings.pop.ssl
      require "pop" # require from this folder
    else
      require "net/pop"
    end

    if settings.smtp.ssl
      require "smtp" # same here
    else
      require "net/smtp"
    end
  end

  def self.get_mails
    if settings.pop.ssl
      Net::POP3.enable_ssl(OpenSSL::SSL::VERIFY_NONE)
    end

    pop = Net::POP3.new(settings.pop.host, settings.pop.port)
    pop.start(settings.pop.user, settings.pop.password)
    if pop.mails.empty?
      Debug::info "No mail."
    else
      i = 0
      pop.mails.each do |m|
        Debug::info "getting mail ##{i}"
        mail_filename = "#{settings.storage.new}/#{Time.now.strftime("%Y-%m-%d--%H-%M-%S--#{i}")}.mail"
        File.open(mail_filename, 'w') do |f|
          f.write m.pop
        end
        m.delete
        i += 1
      end
      Debug::info "#{pop.mails.size} mails popped."
    end
    pop.finish
  end

  def self.process_mails
    mails = Dir[settings.storage.new + "/*.mail"]
    mails.each do |mail_file|
      Debug::info "processing mail: #{mail_file}"

      mail = TMail::Mail.load(mail_file)
      pp mail.content_type
      if mail.multipart?
        Debug::info "Mail is multipart!"
        gpg_ctx = GPGME::Ctx.new(:armor => true)

        # check if message is decrypted
        if mail.attachments.first.lines.first =~ /BEGIN PGP MESSAGE/
          #decrypted_mail = GPG::decrypt_message(mail.attachments.first.gets(nil))
          decrypted_mail = gpg_ctx.decrypt(mail.attachments.first)
          puts "decrypt result: #{gpg_ctx.decrypt_result.inspect}"
          from = mail.from # save from adress
          mail = TMail::Mail.parse(decrypted_mail)
          mail.from = from
        end

        Debug::info "Mail has got #{mail.attachments.size} attachments!"

        mail.attachments.each do |at|
          if settings.allowed_content_types.any?{ |ct| at.content_type == ct }
            pp at
            Debug::info "found gpg key attachment!"

            filename = File.basename(mail_file)
            gpgkey_file = settings.storage.attachments + "/#{filename}.gpgkey"

            File.open(gpgkey_file, "w+") do |f|
              f << at.gets(nil) # save gpg key to file
            end

            send_encrypted_reply(gpg_ctx, gpgkey_file, mail.from)
          end
        end
      end

      Debug::info "done. moving mail #{mail_file} to processed/"
      FileUtils.move(mail_file, settings.storage.processed)
    end
  end

  def self.send_encrypted_reply(gpg_ctx, gpgkey_file, receiver)
    #recv_key_id = GPG::import_key(gpgkey_file)
    key = File.open(gpgkey_file)
    gpg_ctx.import(GPGME::Data.from_str(key.readlines.join))

    imported = gpg_ctx.import_result.imports.first
    
    if imported
      recv_key_id = imported.fpr
    end

    if recv_key_id
      Debug::info "got key_id: #{recv_key_id}"
    else
      Debug::error "got no gpg key id! (returning)"
      return
    end

    # create the base mail-container
    container = TMail::Mail.new
    container['User-Agent'] = settings.reply.user_agent
    container.date = Time.now
    container.subject = settings.reply.subject
    container.to = receiver
    container.from = settings.reply.from
    container.mime_version = '1.0'
    container.set_content_disposition('inline')
    container.body = ""

    # create another Mail-object that holds gpg-attachment
    gpg_container = TMail::Mail.new
    gpg_container.body = "Version: 1\n"
    gpg_container.set_content_type('application','pgp-encrypted')
    gpg_container.set_content_disposition('attachment')

    container.parts.push(gpg_container)

    # finally create the gpg-attachment
    att = TMail::Mail.new
    att.set_content_type('application','octet-stream')
    att.set_content_disposition('inline',
                                'filename' => "encrypted_message")

    #att.body = GPG::encrypt_message(settings.reply.signature.key_id, recv_key_id, settings.reply.message)

    signer_key = gpg_ctx.keys(settings.reply.signature.key_id).first
    recv_key = gpg_ctx.keys(recv_key_id).first

    gpg_ctx.add_signer(signer_key)

    att.body = gpg_ctx.encrypt(recv_key, GPGME::Data.from_str(settings.reply.message))
    container.parts.push(att)

    container.set_content_type('multipart','encrypted',
                               'protocol' => "application/pgp-encrypted")

    # finally, send email as reply
    send_mail container
  end

  def self.send_mail(mail)
    smtp = Net::SMTP.new(settings.smtp.host, settings.smtp.port)
    
    if settings.smtp.ssl
      smtp.enable_ssl
    end
   
    smtp.start("localhost.localdomain", settings.smtp.user, settings.smtp.password, :plain) do |smtp|
      Debug::info "connected to smtp with user: #{settings.smtp.user} to host #{settings.smtp.host}"
      smtp.send_message mail.to_s, mail.from, mail.to
      Debug::info "sent encrypted reply to #{mail.to}"
    end
  end
end
