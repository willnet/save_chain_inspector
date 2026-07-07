# frozen_string_literal: true

require_relative 'save_chain_inspector/version'

class SaveChainInspector # rubocop:disable Metrics/ClassLength, Style/Documentation
  SAVE_METHODS = %i[save save!].freeze
  SAVE_CALLBACK_NAMES = %i[validation save create update].freeze
  CALLBACK_KINDS = %i[before after around].freeze
  INTERNAL_CALLBACK_FILTER_PATTERNS = [
    /\Aautosave_associated_records_for_/,
    /\A_ensure_no_duplicate_errors\z/,
    /\Anormalize_changed_in_place_attributes\z/,
    /\Aaround_save_collection_association\z/
  ].freeze
  INTERNAL_GEM_NAMES = %w[activerecord activemodel activesupport].freeze

  class CallbackLogger # :nodoc:
    CALLBACK_METHOD_PATTERN = /\A(?:before|after|around)_(?:validation|save|create|update)\z/

    def initialize(callback)
      @callback = callback
      @filter = callback.filter
      @label = callback_label(@filter)
    end

    def self.wraps?(filter)
      filter.is_a?(self)
    end

    def method_missing(method_name, target, *_args, &block)
      return super unless callback_method?(method_name) && target

      call_with_logging(target, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      callback_method?(method_name) || super
    end

    private

    def callback_method?(method_name)
      method_name.to_s.match?(CALLBACK_METHOD_PATTERN)
    end

    def call_with_logging(target, &block)
      logged = SaveChainInspector.enable
      return call_original(target, &block) unless logged

      label = "#{target.class}##{@label}"
      SaveChainInspector.log_start(label)
      call_original(target, &block)
    ensure
      SaveChainInspector.log_end(label) if logged
    end

    def call_original(target, &block)
      ActiveSupport::Callbacks::CallTemplate.build(@filter, @callback).make_lambda.call(target, nil, &block)
    end

    def callback_label(filter)
      case filter
      when Symbol
        filter
      when Proc
        block_callback_label(filter)
      else
        filter.class.name || filter.class.to_s
      end
    end

    def block_callback_label(filter)
      source_location = filter.source_location
      return 'block_callback' unless source_location

      "block_callback(#{source_location[0]}:#{source_location[1]})"
    end
  end

  class << self
    attr_accessor :indent_count, :enable, :pending_start, :output

    def start(to: $stdout, &block)
      with_output(to) { inspect_save_chain(&block) }
    end

    def indent
      ' ' * (indent_count * 2)
    end

    def increment_indent
      self.indent_count += 1
    end

    def decrement_indent
      self.indent_count -= 1 if indent_count.positive?
    end

    def log_start(label, collapsible: true)
      flush_pending_start
      if collapsible
        self.pending_start = [indent_count, label]
      else
        write_log "#{indent}#{label} start"
      end
      increment_indent
    end

    def log_end(label, collapsible: true)
      decrement_indent
      if collapsible && pending_start == [indent_count, label]
        write_log "#{indent}#{label} start/end"
        self.pending_start = nil
      else
        flush_pending_start
        write_log "#{indent}#{label} end"
      end
    end

    def flush_pending_start
      return unless pending_start

      pending_indent_count, label = pending_start
      write_log "#{' ' * (pending_indent_count * 2)}#{label} start"
      self.pending_start = nil
    end

    def write_log(message)
      output.puts(message)
    end

    private

    def inspect_save_chain(&block)
      self.indent_count = 0
      self.pending_start = nil
      self.enable = true
      new.call(&block)
    ensure
      flush_pending_start
      self.enable = false
      self.pending_start = nil
    end

    def with_output(to)
      previous_output = output
      current_output, close_output = output_for(to)
      self.output = current_output
      yield
    ensure
      current_output.close if close_output
      self.output = previous_output
    end

    def output_for(to)
      return [to, false] if to.respond_to?(:puts)
      return [File.open(to, 'w'), true] if path_like?(to)

      raise ArgumentError, 'to must be a path or an object that responds to #puts'
    end

    def path_like?(object)
      object.is_a?(String) || object.respond_to?(:to_path)
    end
  end

  def initialize
    ActiveRecord::Base.descendants.each do |klass|
      next if klass.abstract_class
      next if klass.instance_variable_get(:@save_chain_inspector_initialized)

      klass.instance_variable_set(:@save_chain_inspector_initialized, true)
      instrument_model_callbacks(klass)
      add_hooks(klass)
    end
  end

  attr_accessor :last_call_method, :last_call_class, :last_return_method, :last_return_class

  def instrument_model_callbacks(klass)
    SAVE_CALLBACK_NAMES.each do |callback_name|
      chain = klass.send(:get_callbacks, callback_name)
      next if chain.nil? || chain.empty?

      instrumented_chain = chain.dup
      chain.each do |callback|
        next unless instrumentable_callback?(klass, callback)

        replace_callback(instrumented_chain, callback)
      end
      klass.send(:set_callbacks, callback_name, instrumented_chain)
    end
  end

  def instrumentable_callback?(klass, callback)
    CALLBACK_KINDS.include?(callback.kind) &&
      !CallbackLogger.wraps?(callback.filter) &&
      !internal_callback?(klass, callback)
  end

  def replace_callback(chain, callback)
    index = chain.index(callback)
    return unless index

    wrapped_callback = ActiveSupport::Callbacks::Callback.build(
      chain,
      CallbackLogger.new(callback),
      callback.kind,
      callback_options(callback)
    )
    chain.delete(callback)
    chain.insert(index, wrapped_callback)
  end

  def callback_options(callback)
    {
      if: callback.instance_variable_get(:@if),
      unless: callback.instance_variable_get(:@unless)
    }
  end

  def internal_callback?(klass, callback)
    filter = callback.filter
    internal_callback_filter_name?(filter) || rails_internal_callback?(klass, callback)
  end

  def internal_callback_filter_name?(filter)
    return false unless filter.is_a?(Symbol) || filter.is_a?(String)

    INTERNAL_CALLBACK_FILTER_PATTERNS.any? { |pattern| filter.to_s.match?(pattern) }
  end

  def rails_internal_callback?(klass, callback)
    source_location = callback_source_location(klass, callback)
    source_location && internal_gem_source?(source_location[0])
  end

  def callback_source_location(klass, callback)
    source_location_for_callback_filter(klass, callback)
  rescue NameError
    nil
  end

  def source_location_for_callback_filter(klass, callback)
    filter = callback.filter
    case filter
    when Symbol
      symbol_callback_source_location(klass, filter)
    when Proc
      filter.source_location
    else
      object_callback_source_location(callback)
    end
  end

  def symbol_callback_source_location(klass, filter)
    klass.instance_method(filter).source_location
  end

  def object_callback_source_location(callback)
    method_name = callback.current_scopes.join('_').to_sym
    callback.filter.method(method_name).source_location
  rescue NameError
    nil
  end

  def internal_gem_source?(path)
    return false unless path

    INTERNAL_GEM_NAMES.any? do |gem_name|
      gem_path = Gem.loaded_specs[gem_name]&.full_gem_path
      gem_path && path.start_with?(gem_path)
    end
  end

  def add_hooks(klass) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    klass.before_save(prepend: true) do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.log_start("#{model.class}#before_save")
    end
    klass.before_save do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.log_end("#{model.class}#before_save")
    end
    klass.set_callback(:create, :after) do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.log_start("#{model.class}#after_create")
    end
    klass.after_create do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.log_end("#{model.class}#after_create")
    end
    klass.set_callback(:update, :after) do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.log_start("#{model.class}#after_update")
    end
    klass.after_update do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.log_end("#{model.class}#after_update")
    end
  end

  def autosave_method?(trace_point)
    trace_point.method_id.match?(/autosave_associated_records_for_/)
  end

  def save_method?(trace_point)
    SAVE_METHODS.include?(trace_point.method_id)
  end

  def duplicate_save_method_call?(trace_point)
    last_call_method == trace_point.method_id && last_call_class == trace_point.self.class
  end

  def duplicate_save_method_return?(trace_point)
    last_return_method == trace_point.method_id && last_return_class == trace_point.self.class
  end

  def autosave_to_save?(trace_point)
    save_method?(trace_point) && last_call_method&.match?(/autosave_associated_records_for_/)
  end

  def update_last_call(trace_point)
    self.last_call_class = trace_point.self.class
    self.last_call_method = trace_point.method_id
  end

  def update_last_return(trace_point)
    self.last_return_class = trace_point.self.class
    self.last_return_method = trace_point.method_id
  end

  def call(&block)
    trace.enable
    block.yield
  ensure
    trace.disable
  end

  def trace # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @trace ||= TracePoint.new(:call, :return) do |trace_point|
      if trace_point.event == :call
        if autosave_method?(trace_point) || (save_method?(trace_point) && !duplicate_save_method_call?(trace_point))
          update_last_call(trace_point)
          self.class.log_start(
            "#{trace_point.self.class.name}##{trace_point.method_id}",
            collapsible: autosave_method?(trace_point)
          )
        end
      else # :return
        if save_method?(trace_point) && !duplicate_save_method_return?(trace_point)
          update_last_return(trace_point)
          self.class.log_end("#{trace_point.self.class.name}##{trace_point.method_id}", collapsible: false)
        end

        self.class.log_end("#{trace_point.self.class.name}##{trace_point.method_id}") if autosave_method?(trace_point)
      end
    end
  end
end
