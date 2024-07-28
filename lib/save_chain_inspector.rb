# frozen_string_literal: true

require_relative 'save_chain_inspector/version'

class SaveChainInspector # rubocop:disable Metrics/ClassLength, Style/Documentation
  class << self
    attr_accessor :indent, :enable
  end

  self.indent = 0
  self.enable = false
  def self.start(&block)
    self.indent = 0
    self.enable = true
    new.call(&block)
  ensure
    self.enable = false
  end

  def initialize
    ActiveRecord::Base.descendants.each do |klass|
      next if klass.abstract_class
      next if @save_chain_inspector_initialized

      @save_chain_inspector_initialized = true
      add_hooks(klass)
    end
  end

  attr_accessor :last_call_method, :last_call_class, :last_return_method, :last_return_class

  def add_hooks(klass) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    klass.before_save(prepend: true) do |model|
      next unless SaveChainInspector.enable

      puts "#{' ' * (SaveChainInspector.indent * 2)}#{model.class}#before_save start"
      SaveChainInspector.indent += 1
    end
    klass.before_save do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.indent -= 1
      puts "#{' ' * (SaveChainInspector.indent * 2)}#{model.class}#before_save end"
    end
    klass.set_callback(:create, :after) do |model|
      next unless SaveChainInspector.enable

      puts "#{' ' * (SaveChainInspector.indent * 2)}#{model.class}#after_create start"
      SaveChainInspector.indent += 1
    end
    klass.after_create do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.indent -= 1
      puts "#{' ' * (SaveChainInspector.indent * 2)}#{model.class}#after_create end"
    end
    klass.set_callback(:update, :after) do |model|
      next unless SaveChainInspector.enable

      puts "#{' ' * (SaveChainInspector.indent * 2)}#{model.class}#after_update start"
      SaveChainInspector.indent += 1
    end
    klass.after_update do |model|
      next unless SaveChainInspector.enable

      SaveChainInspector.indent -= 1
      puts "#{' ' * (SaveChainInspector.indent * 2)}#{model.class}#after_update end"
    end
  end

  def autosave_method?(trace_point)
    trace_point.method_id.match?(/autosave_associated_records_for_/)
  end

  def save_method?(trace_point)
    trace_point.method_id == :save || trace_point.method_id == :save!
  end

  def duplicate_save_method_call?(trace_point)
    last_call_method == trace_point.method_id && last_call_class == trace_point.self.class
  end

  def duplicate_save_method_return?(trace_point)
    last_return_method == trace_point.method_id && last_return_class == trace_point.self.class
  end

  def autosave_to_save?(trace_point)
    (trace_point.method_id == :save || trace_point.method_id == :save!) &&
      last_call_method&.match?(/autosave_associated_records_for_/)
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
          puts "#{' ' * (self.class.indent * 2)}#{trace_point.self.class.name}##{trace_point.method_id} start"
          self.class.indent += 1
        end
      else # :return
        if save_method?(trace_point) && !duplicate_save_method_return?(trace_point)
          self.class.indent -= 1
          update_last_return(trace_point)
          puts "#{' ' * (self.class.indent * 2)}#{trace_point.self.class.name}##{trace_point.method_id} end"
        end

        if autosave_method?(trace_point)
          self.class.indent -= 1
          puts "#{' ' * (self.class.indent * 2)}#{trace_point.self.class.name}##{trace_point.method_id} end"
        end
      end
    end
  end
end
