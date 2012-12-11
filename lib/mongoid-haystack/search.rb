module Mongoid
  module Haystack
    module Search
      ClassMethods = proc do
        def search(*args, &block)
          options = Map.options_for!(args)
          options[:types] = Array(options[:types]).flatten.compact
          options[:types].push(self)
          args.push(options)
          results = Haystack.search(*args, &block)
        end

        def search_index_all!
          all.each do |doc|
            Mongoid::Haystack::Index.remove(doc)
            Mongoid::Haystack::Index.add(doc)
          end
        end

        after_save do |doc|
          begin
            doc.search_index! if doc.persisted?
          rescue Object
            nil
          end
        end

        after_destroy do |doc|
          begin
            doc.search_unindex! if doc.destroyed?
          rescue Object
            nil
          end
        end

        has_one(:haystack_index, :as => :model, :class_name => '::Mongoid::Haystack::Index')
      end

      InstanceMethods = proc do
        def search_index!
          doc = self
          Mongoid::Haystack::Index.remove(doc)
          Mongoid::Haystack::Index.add(doc)
        end

        def search_unindex!
          doc = self
          Mongoid::Haystack::Index.remove(doc)
        end
      end

      def Search.included(other)
        super
      ensure
        other.instance_eval(&ClassMethods)
        other.class_eval(&InstanceMethods)
      end
    end

    def search(*args, &block)
    #
      options = Map.options_for!(args)
      search = args.join(' ')

      conditions = {}
      order = []

      op = :token_ids.in

    #
      case
        when options[:all]
          op = :token_ids.all
          search += Coerce.string(options[:all])

        when options[:any]
          op = :token_ids.in
          search += Coerce.string(options[:any])

        when options[:in]
          op = :token_ids.in
          search += Coerce.string(options[:in])
      end

    #
      tokens = search_tokens_for(search)
      token_ids = tokens.map{|token| token.id}

    #
      conditions[op] = token_ids

    #
      order.push(["score", :desc])

      tokens.each do |token|
        order.push(["keyword_scores.#{ token.id }", :desc])
      end

      tokens.each do |token|
        order.push(["fulltext_scores.#{ token.id }", :desc])
      end

    #
      if options[:facets]
        conditions[:facets] = {'$elemMatch' => options[:facets]}
      end

    #
      if options[:types]
        model_types = Array(options[:types]).map{|type| type.name}
        conditions[:model_type.in] = model_types
      end

    #
      query =
        Index.where(conditions)
          .order_by(order)
            .only(:_id, :model_type, :model_id)

      query.extend(Pagination)

      query.extend(Denormalization)

      query
    end

    module Denormalization
      def models
        ::Mongoid::Haystack.denormalize(self)
        map(&:model)
      end
    end

    module Pagination
      def paginate(*args, &block)
        list = self
        options = Map.options_for!(args)

        page = Integer(args.shift || options[:page] || 1)
        size = Integer(args.shift || options[:size] || 42)

        count =
          if list.is_a?(Array)
            list.size
          else
            list.count
          end

        limit = size
        skip = (page - 1 ) * size
        
        result =
          if list.is_a?(Array)
            list.slice(skip, limit)
          else
            list.skip(skip).limit(limit)
          end

        result.extend(Result)

        result.paginate.update(
          :total_pages  => (count / size.to_f).ceil,
          :num_pages    => (count / size.to_f).ceil,
          :current_page => page
        )

        result
      end

      module Result
        def paginate
          @paginate ||= Map.new
        end

        def method_missing(method, *args, &block)
          if paginate.has_key?(method) and args.empty? and block.nil?
            paginate[method]
          else
            super
          end
        end
      end
    end

    def search_tokens_for(search)
      values = Token.values_for(search.to_s)
      tokens = Token.where(:value.in => values).to_a

      positions = {}
      tokens.each_with_index{|token, index| positions[token] = index + 1}

      total = Token.total.to_f

      tokens.sort! do |a,b|
        [b.rarity_bin(total), positions[b]] <=> [a.rarity_bin(total), positions[a]]
      end

      tokens
    end

    def Haystack.denormalize(results)
      queries = Hash.new{|h,k| h[k] = []}

      results = results.to_a.flatten.compact

      results.each do |result|
        model_type = result[:model_type]
        model_id = result[:model_id]
        model_class = model_type.constantize
        queries[model_class].push(model_id)
      end

      index = Hash.new{|h,k| h[k] = {}}

      queries.each do |model_class, model_ids|
        models = 
          begin
            model_class.find(model_ids)
          rescue Mongoid::Errors::DocumentNotFound
            model_ids.map do |model_id|
              begin
                model_class.find(model_id)
              rescue Mongoid::Errors::DocumentNotFound
                nil
              end
            end
          end

        models.each do |model|
          index[model.class.name] ||= Hash.new
          next unless model
          index[model.class.name][model.id.to_s] = model
        end
      end

      to_ignore = []

      results.each_with_index do |result, i|
        model = index[result['model_type']][result['model_id'].to_s]

        if model.nil?
          to_ignore.push(i)
          next
        else
          result.model = model
        end

        result.model.freeze
        result.freeze
      end

      to_ignore.reverse.each{|i| results.delete_at(i)}

      results
    end

    def Haystack.expand(*args, &block)
      Haystack.denormalize(*args, &block)
    end

    def Haystack.models_for(*args, &block)
      Haystack.denormalize(*args, &block).map(&:model)
    end
  end
end
