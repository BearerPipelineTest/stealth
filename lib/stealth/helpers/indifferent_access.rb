# frozen_string_literal: true

module Stealth
  # A poor man's ActiveSupport::HashWithIndifferentAccess, with all the Rails-y
  # stuff removed.
  #
  # Implements a hash where keys <tt>:foo</tt> and <tt>"foo"</tt> are
  # considered to be the same.
  #
  #   rgb = Stealth::IndifferentHash.new
  #
  #   rgb[:black]    =  '#000000' # symbol assignment
  #   rgb[:black]  # => '#000000' # symbol retrieval
  #   rgb['black'] # => '#000000' # string retrieval
  #
  #   rgb['white']   =  '#FFFFFF' # string assignment
  #   rgb[:white]  # => '#FFFFFF' # symbol retrieval
  #   rgb['white'] # => '#FFFFFF' # string retrieval
  #
  # Internally, symbols are mapped to strings when used as keys in the entire
  # writing interface (calling e.g. <tt>[]=</tt>, <tt>merge</tt>). This mapping
  # belongs to the public interface. For example, given:
  #
  #   hash = Stealth::IndifferentHash.new(:a=>1)
  #
  # You are guaranteed that the key is returned as a string:
  #
  #   hash.keys # => ["a"]
  #
  # Technically other types of keys are accepted:
  #
  #   hash = Stealth::IndifferentHash.new(:a=>1)
  #   hash[0] = 0
  #   hash # => { "a"=>1, 0=>0 }
  #
  # But this class is intended for use cases where strings or symbols are the
  # expected keys and it is convenient to understand both as the same. For
  # example the +params+ hash in Stealth.
  class IndifferentHash < Hash
    # Returns +true+ so that <tt>Array#extract_options!</tt> finds members of
    # this class.
    def extractable_options?
      true
    end

    def with_indifferent_access
      dup
    end

    def nested_under_indifferent_access
      self
    end

    def initialize(constructor = {})
      if constructor.respond_to?(:to_hash)
        super()
        update(constructor)

        hash = constructor.to_hash
        self.default = hash.default if hash.default
        self.default_proc = hash.default_proc if hash.default_proc
      else
        super(constructor)
      end
    end

    def self.[](*args)
      new.merge!(Hash[*args])
    end

    alias_method :regular_writer, :[]= unless method_defined?(:regular_writer)
    alias_method :regular_update, :update unless method_defined?(:regular_update)

    # Assigns a new value to the hash:
    #
    #   hash = Stealth::IndifferentHash.new
    #   hash[:key] = 'value'
    #
    # This value can be later fetched using either +:key+ or <tt>'key'</tt>.
    def []=(key, value)
      regular_writer(convert_key(key), convert_value(value, for: :assignment))
    end

    alias_method :store, :[]=

    # Updates the receiver in-place, merging in the hash passed as argument:
    #
    #   hash_1 = Stealth::IndifferentHash.new
    #   hash_1[:key] = 'value'
    #
    #   hash_2 = Stealth::IndifferentHash.new
    #   hash_2[:key] = 'New Value!'
    #
    #   hash_1.update(hash_2) # => {"key"=>"New Value!"}
    #
    # The argument can be either an
    # <tt>Stealth::IndifferentHash</tt> or a regular +Hash+.
    # In either case the merge respects the semantics of indifferent access.
    #
    # If the argument is a regular hash with keys +:key+ and +"key"+ only one
    # of the values end up in the receiver, but which one is unspecified.
    #
    # When given a block, the value for duplicated keys will be determined
    # by the result of invoking the block with the duplicated key, the value
    # in the receiver, and the value in +other_hash+. The rules for duplicated
    # keys follow the semantics of indifferent access:
    #
    #   hash_1[:key] = 10
    #   hash_2['key'] = 12
    #   hash_1.update(hash_2) { |key, old, new| old + new } # => {"key"=>22}
    def update(other_hash)
      if other_hash.is_a? IndifferentHash
        super(other_hash)
      else
        other_hash.to_hash.each_pair do |key, value|
          if block_given? && key?(key)
            value = yield(convert_key(key), self[key], value)
          end
          regular_writer(convert_key(key), convert_value(value))
        end
        self
      end
    end

    alias_method :merge!, :update

    # Checks the hash for a key matching the argument passed in:
    #
    #   hash = Stealth::IndifferentHash.new
    #   hash['key'] = 'value'
    #   hash.key?(:key)  # => true
    #   hash.key?('key') # => true
    def key?(key)
      super(convert_key(key))
    end

    alias_method :include?, :key?
    alias_method :has_key?, :key?
    alias_method :member?, :key?

    # Same as <tt>Hash#[]</tt> where the key passed as argument can be
    # either a string or a symbol:
    #
    #   counters = Stealth::IndifferentHash.new
    #   counters[:foo] = 1
    #
    #   counters['foo'] # => 1
    #   counters[:foo]  # => 1
    #   counters[:zoo]  # => nil
    def [](key)
      super(convert_key(key))
    end

    # Same as <tt>Hash#fetch</tt> where the key passed as argument can be
    # either a string or a symbol:
    #
    #   counters = Stealth::IndifferentHash.new
    #   counters[:foo] = 1
    #
    #   counters.fetch('foo')          # => 1
    #   counters.fetch(:bar, 0)        # => 0
    #   counters.fetch(:bar) { |key| 0 } # => 0
    #   counters.fetch(:zoo)           # => KeyError: key not found: "zoo"
    def fetch(key, *extras)
      super(convert_key(key), *extras)
    end

    if Hash.new.respond_to?(:dig)
      # Same as <tt>Hash#dig</tt> where the key passed as argument can be
      # either a string or a symbol:
      #
      #   counters = Stealth::IndifferentHash.new
      #   counters[:foo] = { bar: 1 }
      #
      #   counters.dig('foo', 'bar')     # => 1
      #   counters.dig(:foo, :bar)       # => 1
      #   counters.dig(:zoo)             # => nil
      def dig(*args)
        args[0] = convert_key(args[0]) if args.size > 0
        super(*args)
      end
    end

    # Same as <tt>Hash#default</tt> where the key passed as argument can be
    # either a string or a symbol:
    #
    #   hash = Stealth::IndifferentHash.new(1)
    #   hash.default                   # => 1
    #
    #   hash = Stealth::IndifferentHash.new { |hash, key| key }
    #   hash.default                   # => nil
    #   hash.default('foo')            # => 'foo'
    #   hash.default(:foo)             # => 'foo'
    def default(*args)
      super(*args.map { |arg| convert_key(arg) })
    end

    # Returns an array of the values at the specified indices:
    #
    #   hash = Stealth::IndifferentHash.new
    #   hash[:a] = 'x'
    #   hash[:b] = 'y'
    #   hash.values_at('a', 'b') # => ["x", "y"]
    def values_at(*indices)
      indices.collect { |key| self[convert_key(key)] }
    end

    # Returns an array of the values at the specified indices, but also
    # raises an exception when one of the keys can't be found.
    #
    #   hash = Stealth::IndifferentHash.new
    #   hash[:a] = 'x'
    #   hash[:b] = 'y'
    #   hash.fetch_values('a', 'b') # => ["x", "y"]
    #   hash.fetch_values('a', 'c') { |key| 'z' } # => ["x", "z"]
    #   hash.fetch_values('a', 'c') # => KeyError: key not found: "c"
    def fetch_values(*indices, &block)
      indices.collect { |key| fetch(key, &block) }
    end if Hash.method_defined?(:fetch_values)

    # Returns a shallow copy of the hash.
    #
    #   hash = Stealth::IndifferentHash.new({ a: { b: 'b' } })
    #   dup  = hash.dup
    #   dup[:a][:c] = 'c'
    #
    #   hash[:a][:c] # => "c"
    #   dup[:a][:c]  # => "c"
    def dup
      self.class.new(self).tap do |new_hash|
        set_defaults(new_hash)
      end
    end

    # This method has the same semantics of +update+, except it does not
    # modify the receiver but rather returns a new hash with indifferent
    # access with the result of the merge.
    def merge(hash, &block)
      dup.update(hash, &block)
    end

    # Replaces the contents of this hash with other_hash.
    #
    #   h = { "a" => 100, "b" => 200 }
    #   h.replace({ "c" => 300, "d" => 400 }) # => {"c"=>300, "d"=>400}
    def replace(other_hash)
      super(self.class.new(other_hash))
    end

    # Removes the specified key from the hash.
    def delete(key)
      super(convert_key(key))
    end

    def to_options!; self end

    def select(*args, &block)
      return to_enum(:select) unless block_given?
      dup.tap { |hash| hash.select!(*args, &block) }
    end

    def reject(*args, &block)
      return to_enum(:reject) unless block_given?
      dup.tap { |hash| hash.reject!(*args, &block) }
    end

    def transform_values(*args, &block)
      return to_enum(:transform_values) unless block_given?
      dup.tap { |hash| hash.transform_values!(*args, &block) }
    end

    def compact
      dup.tap(&:compact!)
    end

    # Convert to a regular hash with string keys.
    def to_hash
      _new_hash = Hash.new
      set_defaults(_new_hash)

      each do |key, value|
        _new_hash[key] = convert_value(value, for: :to_hash)
      end
      _new_hash
    end

    private
      def convert_key(key) # :doc:
        key.kind_of?(Symbol) ? key.to_s : key
      end

      def convert_value(value, options = {}) # :doc:
        if value.is_a? Hash
          if options[:for] == :to_hash
            value.to_hash
          else
            value.nested_under_indifferent_access
          end
        elsif value.is_a?(Array)
          if options[:for] != :assignment || value.frozen?
            value = value.dup
          end
          value.map! { |e| convert_value(e, options) }
        else
          value
        end
      end

      def set_defaults(target) # :doc:
        if default_proc
          target.default_proc = default_proc.dup
        else
          target.default = default
        end
      end
  end
end

# :stopdoc:

IndifferentHash = Stealth::IndifferentHash

class Hash
  # Returns an <tt>Stealth::IndifferentHash</tt> out of its receiver:
  #
  #   { a: 1 }.with_indifferent_access['a'] # => 1
  def with_indifferent_access
    Stealth::IndifferentHash.new(self)
  end

  # Called when object is nested under an object that receives
  # #with_indifferent_access. This method will be called on the current object
  # by the enclosing object and is aliased to #with_indifferent_access by
  # default. Subclasses of Hash may overwrite this method to return +self+ if
  # converting to an <tt>Stealth::IndifferentHash</tt> would not be
  # desirable.
  #
  #   b = { b: 1 }
  #   { a: b }.with_indifferent_access['a'] # calls b.nested_under_indifferent_access
  #   # => {"b"=>1}
  alias nested_under_indifferent_access with_indifferent_access
end