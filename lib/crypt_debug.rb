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

module Cryptmail
  module Debug
    @@debug_on = false
    @@io = STDOUT

    def self.io
      @@io if @@io != STDOUT
    end
    
    def self.io= io
      @@io = io
    end

    def self.enable
      @@debug_on = true
    end

    def self.disable
      @@debug_on = false
    end
    
    def self.info msg
      @@io.puts ">> #{msg}" if @@debug_on
    end

    def self.error msg
      @@io.puts "error>> #{msg}" if @@debug_on
    end

    def self.warning msg
      @@io.puts "warning>> #{msg}" if @@debug_on
    end
  end  
end
