# frozen_string_literal: true

require_relative 'save_chain_inspector/version'

class SaveChainInspector
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
  end

  attr_accessor :last_call_method, :last_call_class, :last_return_method, :last_return_class

  def autosave_method?(tp)
    tp.method_id.match?(/autosave_associated_records_for_/)
  end

  def save_method?(tp)
    tp.method_id == :save || tp.method_id == :save!
  end

  def duplicate_save_method_call?(tp)
    last_call_method == tp.method_id && last_call_class == tp.self.class
  end

  def duplicate_save_method_return?(tp)
    last_return_method == tp.method_id && last_return_class == tp.self.class
  end

  def autosave_to_save?(tp)
    (tp.method_id == :save || tp.method_id == :save!) && last_call_method&.match?(/autosave_associated_records_for_/)
  end

  def update_last_call(tp)
    self.last_call_class = tp.self.class
    self.last_call_method = tp.method_id
  end

  def update_last_return(tp)
    self.last_return_class = tp.self.class
    self.last_return_method = tp.method_id
  end

  def call(&block)
    trace = TracePoint.new(:call, :return) do |tp|
      if tp.event == :call
        if autosave_method?(tp)
          update_last_call(tp)
          puts "#{' ' * (self.class.indent * 2)}#{tp.self.class.name}##{tp.method_id} start"
          self.class.indent += 1
        elsif save_method?(tp) && !duplicate_save_method_call?(tp)
          update_last_call(tp)
          puts "#{' ' * (self.class.indent * 2)}#{tp.self.class.name}##{tp.method_id} start"
          self.class.indent += 1
        end
      else # :return
        if save_method?(tp) && !duplicate_save_method_return?(tp)
          self.class.indent -= 1
          update_last_return(tp)
          puts "#{' ' * (self.class.indent * 2)}#{tp.self.class.name}##{tp.method_id} end"
        end

        if autosave_method?(tp)
          self.class.indent -= 1
          puts "#{' ' * (self.class.indent * 2)}#{tp.self.class.name}##{tp.method_id} end"
        end
      end
    end
    trace.enable
    block.yield
    trace.disable
  end
end
