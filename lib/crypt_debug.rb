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
