##
#
  module Mongoid
    module Haystack
      const_set :Version, '1.2.1'

      class << Haystack
        def version
          const_get :Version
        end

        def dependencies
          {
            'mongoid'       => [ 'mongoid'       , '~> 3.0.14' ] , 
            'moped'         => [ 'moped'         , '~> 1.3.1'  ] , 
            'origin'        => [ 'origin'        , '~> 1.0.11' ] , 
            'map'           => [ 'map'           , '~> 6.2'    ] , 
            'fattr'         => [ 'fattr'         , '~> 2.2'    ] , 
            'coerce'        => [ 'coerce'        , '~> 0.0.3'  ] , 
            'unicode_utils' => [ 'unicode_utils' , '~> 1.4.0'  ] , 
          }
        end

        def libdir(*args, &block)
          @libdir ||= File.expand_path(__FILE__).sub(/\.rb$/,'')
          args.empty? ? @libdir : File.join(@libdir, *args)
        ensure
          if block
            begin
              $LOAD_PATH.unshift(@libdir)
              block.call()
            ensure
              $LOAD_PATH.shift()
            end
          end
        end

        def load(*libs)
          libs = libs.join(' ').scan(/[^\s+]+/)
          libdir{ libs.each{|lib| Kernel.load(lib) } }
        end
      end

      begin
        require 'rubygems'
      rescue LoadError
        nil
      end

      if defined?(gem)
        dependencies.each do |lib, dependency|
          gem(*dependency)
          require(lib)
        end
      end

      begin
        require 'pry'
      rescue LoadError
        nil
      end

      begin
        require 'fast_stemmer'
      rescue LoadError
        begin
          require 'stemmer'
        rescue LoadError
          abort("mongoid-haystack requires either the 'fast-stemmer' or 'ruby-stemmer' gems")
        end
      end

      require 'unicode_utils/u'
      require 'unicode_utils/each_word'

      load Haystack.libdir('stemming.rb')
      load Haystack.libdir('util.rb')
      load Haystack.libdir('sequence.rb')
      load Haystack.libdir('token.rb')
      load Haystack.libdir('index.rb')
      load Haystack.libdir('search.rb')

      def Haystack.included(other)
        other.send(:include, Search)
      end

      extend Haystack
    end
  end

##
#
  if defined?(Rails)
    class Mongoid::Haystack::Engine < Rails::Engine
      paths['app/models'] = File.dirname(__FILE__)
    end
  end
