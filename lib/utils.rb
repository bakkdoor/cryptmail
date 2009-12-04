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
  ## Tries to import a gpg key from a given filename.
  ## If import succeeds, returns its key id (hexadecimal hashvalue) as
  ## a string.
  ## Otherwise returns nil.
  def self.import_key(gpgkey_file)
    key = nil
    stdin, stdout, stderr = Open3.popen3 "gpg --batch --import #{gpgkey_file}"
    stderr.each do |line|
      if line =~ /^gpg: (Schl.+ssel|key) (\S+):/
        key = $2
      end
    end
    key
  end

  ## Runs the gpg command and yields an input-stream to gpg to a given
  ## block.
  ## Finally returns the output of running gpg with a given command.
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

  ## Signs a given message with a gpg key (specified via key_id) and
  ## Returns the signed message as a string.
  def self.sign_message(key_id, message)
    puts ">> signing message with key_id: #{key_id}"
    run_gpg "--default-key #{key_id} --clearsign" do |input|
      input.puts message
    end
  end

  ## Encrypts a message (string) with a given key for a receiver key id.
  ## Returns the encrypted message as a string.
  def self.encrypt_message(sign_key_id, recv_key_id, message)
    message = sign_message(sign_key_id, message)
    run_gpg "--always-trust -r #{recv_key_id} -ea" do |input|
      input.puts message
    end      
  end

  ## Decrypts a given message (string) and returns the decrypted
  ## message as a string.
  def self.decrypt_message(message)
    run_gpg "--decrypt", false do |input|
      input.puts message
    end
  end
end
