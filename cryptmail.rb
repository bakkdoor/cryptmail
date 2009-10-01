#!/usr/bin/env ruby

require "rubygems"
require "tmail"
require "net/pop"
require "net/smtp"
require "fileutils"
require "pp"
require "open3"
require "yaml"

class Hash
  def method_missing(*args)
    val = self
    args.each do |a|
      if val.is_a?(Hash)
        val = val[a.to_s]
      else
        val = val.send(a.to_s)
      end
    end
    val
  end
end

def settings
  @@yaml ||= YAML::load_file("config.yaml")
end

def get_mails
  pop = Net::POP3.new(settings.pop.host, settings.pop.port)
  pop.start(settings.pop.user, settings.pop.password)
  if pop.mails.empty?
    puts ">> No mail."
  else
    i = 0
    pop.mails.each do |m|
      puts ">> getting mail ##{i}"
      mail_filename = "#{settings.storage.new}/#{Time.now.strftime("%Y-%m-%d--%H-%M-%S--#{i}")}.mail"
      File.open(mail_filename, 'w') do |f|
        f.write m.pop
      end
      m.delete
      i += 1
    end
    puts ">> #{pop.mails.size} mails popped."
  end
  pop.finish
end

def process_mails
  mails = Dir[settings.storage.new + "/*.mail"]
  mails.each do |mail_file|
    puts ">> processing mail: #{mail_file}"

    mail = TMail::Mail.load(mail_file)
    pp mail.content_type
    if mail.multipart?
      puts ">> Mail is multipart!"
      puts ">> Mail has got #{mail.attachments.size} attachments!"

      mail.attachments.each do |at|
        if settings.allowed_content_types.any?{ |ct| at.content_type == ct }
          pp at
          puts ">> found gpg key attachment!"

          filename = File.basename(mail_file)
          gpgkey_file = settings.storage.attachments + "/#{filename}.gpgkey"

          File.open(gpgkey_file, "w+") do |f|
            f << at.gets(nil) # save gpg key to file
          end

          send_encrypted_reply(gpgkey_file, mail.from)
        end
      end
    end

    puts ">> done. moving mail #{mail_file} to processed/"
    FileUtils.move(mail_file, settings.storage.processed)
  end
end

def import_key(gpgkey_file)
  key = nil

  stdin, stdout, stderr = Open3.popen3 "gpg --batch --import #{gpgkey_file}"

  stderr.each do |line|
    if line =~ /^gpg: Schlüssel (\S+):/
      key = $1
    end
  end
  key
end

def send_encrypted_reply(gpgkey_file, receiver)
  key_id = import_key(gpgkey_file)

  if key_id
    puts ">> got key_id: #{key_id}"
  else
    puts ">> error: got no gpg key id! (returning)"
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

  att.body = encrypt_message(key_id, settings.reply.message)
  container.parts.push(att)

  container.set_content_type('multipart','encrypted',
                             'protocol' => "application/pgp-encrypted")

  # finally, send email as reply
  send_mail container
end

def encrypt_message(key_id, message)
  i, o, e = Open3.popen3 "gpg --always-trust --batch -r #{key_id} -ea"
  i.puts key_id
  i.puts message
  i.close

  encrypted_msg = []
  o.each do |l|
    encrypted_msg << l
  end

  e.each do |l|
    puts "error>> #{l}"
  end

  encrypted_msg.join
end

def send_mail(mail)
  smtp = Net::SMTP.new(settings.smtp.host, settings.smtp.port)
  smtp.start("localhost.localdomain", settings.smtp.user, settings.smtp.password) do |smtp|
    puts "connected to smtp.."
    smtp.send_message mail.to_s, mail.from, mail.to
    puts "sent encrypted reply to #{mail.to}"
  end
end

# main programm
sleep_hours = settings.interval.hours.to_i
sleep_mins = settings.interval.minutes.to_i
sleep_secs = settings.interval.seconds.to_i
sleep_time = sleep_hours * 3600 + sleep_mins * 60 + sleep_secs

puts ">> programm interval is: #{sleep_hours}:#{sleep_mins}:#{sleep_secs}"
puts "storing new mails to: #{settings.storage.new}"
puts ">> starting execution"
puts

loop do
  get_mails
  process_mails
  sleep(sleep_time)
end
