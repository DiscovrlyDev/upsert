require 'zlib'

class Upsert
  # @private
  class MergeFunction
    MAX_NAME_LENGTH = 62

    class << self
      def execute(controller, row)
        merge_function = lookup controller, row
        merge_function.execute row
      end

      def unique_name(table_name, selector_keys, setter_keys)
        parts = [
          'upsert',
          table_name,
          'SEL',
          selector_keys.join('_A_'),
          'SET',
          setter_keys.join('_A_')
        ].join('_')
        if parts.length > MAX_NAME_LENGTH
          # maybe i should md5 instead
          crc32 = Zlib.crc32(parts).to_s
          [ parts[0..MAX_NAME_LENGTH-10], crc32 ].join
        else
          parts
        end
      end

      def lookup(controller, row)
        @lookup ||= {}
        selector_keys = row.selector.keys
        setter_keys = row.setter.keys
        options = row.options
        key = [controller.table_name, selector_keys, setter_keys]
        @lookup[key] ||= new(controller, selector_keys, setter_keys, options, controller.assume_function_exists?)
      end
    end

    attr_reader :controller
    attr_reader :selector_keys
    attr_reader :setter_keys
    attr_reader :options

    def initialize(controller, selector_keys, setter_keys, options, assume_function_exists)
      @controller = controller
      @selector_keys = selector_keys
      @setter_keys = setter_keys
      @options = options
      validate!
      create! unless assume_function_exists
    end

    def name
      @name ||= MergeFunction.unique_name table_name, selector_keys, setter_keys
    end

    def connection
      controller.connection
    end

    def table_name
      controller.table_name
    end

    def quoted_table_name
      controller.quoted_table_name
    end

    def column_definitions
      controller.column_definitions
    end

    private

    def validate!
      possible = column_definitions.map(&:name)
      ignore_on_update_keys = options[:ignore_on_update] || []
      invalid = (setter_keys + selector_keys + ignore_on_update_keys).uniq - possible
      if invalid.any?
        raise ArgumentError, "[Upsert] Invalid column(s): #{invalid.map(&:inspect).join(', ')}"
      end
    end
  end
end
