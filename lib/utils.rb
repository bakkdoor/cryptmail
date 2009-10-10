# -*- coding: utf-8 -*-
# utils.rb
# some helper methods & extensions for cryptmail

require "fileutils"
require "open3"

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

module GPG
  def self.import_key(gpgkey_file)
    key = nil
    stdin, stdout, stderr = Open3.popen3 "gpg --batch --import #{gpgkey_file}"
    stderr.each do |line|
      if line =~ /^gpg: (Schlüssel|key) (\S+):/
        key = $2
      end
    end
    key
  end

  def self.run_gpg(gpg_cmd, show_errors = true)
    i, o, e = Open3.popen3 "gpg --batch #{gpg_cmd}"
    #i.puts message
    if block_given?
      yield i
    end
    i.close
    
    return_msg = []
    o.each{ |l| return_msg << l }
    if show_errors
      e.each{ |l| puts "gpg-error>> #{l}" }
    end

    return_msg.join
  end

  def self.sign_message(key_id, message)
    puts ">> signing message with key_id: #{key_id}"
    run_gpg "--default-key #{key_id} --clearsign" do |input|
      input.puts message
    end
  end

  def self.encrypt_message(sign_key_id, recv_key_id, message)
    message = sign_message(sign_key_id, message)
    run_gpg "--always-trust -r #{recv_key_id} -ea" do |input|
      input.puts message
    end      
  end

  def self.decrypt_message(message)
    run_gpg "--decrypt", false do |input|
      input.puts message
    end
  end
end
