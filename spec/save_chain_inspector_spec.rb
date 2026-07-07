# frozen_string_literal: true

require 'stringio'
require 'tmpdir'

require 'spec_helper'

RSpec.describe SaveChainInspector do
  let(:expected_output) do
    <<~OUTPUT
      Post#save start
        Post#prepare_post start/end
        Post#before_save start
          Post#normalize_post start/end
        Post#before_save end
        Post#after_create start
          Post#autosave_associated_records_for_comments start
            Comment#save start
              Comment#before_save start
                Comment#autosave_associated_records_for_post start/end
                Comment#normalize_comment start/end
              Comment#before_save end
              Comment#after_create start/end
            Comment#save end
          Post#autosave_associated_records_for_comments end
          Post#notify_created start/end
        Post#after_create end
      Post#save end
    OUTPUT
  end

  it "doesn't write logs for callbacks whose condition is false" do
    expect do
      SaveChainInspector.start do
        Post.create
      end
    end.not_to output(/skipped_post_callback/).to_stdout
  end

  it 'preserves callback conditions derived from on options' do
    string_io = StringIO.new
    CallbackOptionRecord.events.clear

    SaveChainInspector.start(to: string_io) do
      CallbackOptionRecord.create!
    end

    expect(string_io.string).to include('CallbackOptionRecord#create_only_validation start/end')
    expect(CallbackOptionRecord.events).to include(:create_only_validation)
  end

  it 'preserves callback conditions and order while wrapping callbacks' do
    record = CallbackOptionRecord.create!
    string_io = StringIO.new
    CallbackOptionRecord.events.clear

    SaveChainInspector.start(to: string_io) do
      record.save!
    end

    expect(string_io.string).not_to include('CallbackOptionRecord#create_only_validation')
    expect(string_io.string).to match(
      %r{CallbackOptionRecord#prepended_save start/end.*CallbackOptionRecord#appended_save start/end}m
    )
    expect(string_io.string).to include('CallbackOptionRecord#around_save_callback start')
    expect(string_io.string).to include('CallbackOptionRecord#around_save_callback end')
    expect(CallbackOptionRecord.events).to eq(%i[prepended_save appended_save around_before around_after])
  end

  it 'writes logs inside the block' do
    expect do
      SaveChainInspector.start do
        save_post_with_comment
      end
    end.to output(expected_output).to_stdout
  end

  it 'writes logs to a file path' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'save_chain.log')
      File.write(path, 'old log')

      expect do
        SaveChainInspector.start(to: path) do
          save_post_with_comment
        end
      end.not_to output.to_stdout

      expect(File.read(path)).to eq(expected_output)
    end
  end

  it 'writes logs to an IO-like object without closing it' do
    string_io = StringIO.new

    expect do
      SaveChainInspector.start(to: string_io) do
        save_post_with_comment
      end
    end.not_to output.to_stdout

    expect(string_io.string).to eq(expected_output)
    expect(string_io.closed?).to be(false)
  end

  it 'prioritizes IO-like objects over path-like objects' do
    io_like = Class.new do
      attr_reader :string

      def initialize
        @string = +''
        @closed = false
      end

      def puts(message)
        @string << message << "\n"
      end

      def to_path
        raise 'should not use to_path'
      end

      def close
        @closed = true
      end

      def closed?
        @closed
      end
    end.new

    SaveChainInspector.start(to: io_like) do
      save_post_with_comment
    end

    expect(io_like.string).to eq(expected_output)
    expect(io_like.closed?).to be(false)
  end

  it 'restores the outer output target for nested starts' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'save_chain.log')
      inner_io = StringIO.new

      expect do
        SaveChainInspector.start(to: path) do
          SaveChainInspector.start(to: inner_io) do
            expect(SaveChainInspector.output).to be(inner_io)
          end

          expect(SaveChainInspector.output.path).to eq(path)
        end
      end.not_to raise_error

      expect(inner_io.string).to eq('')
      expect(File.read(path)).to eq('')
    end
  end

  it "doesn't write logs outside the block" do
    expect do
      SaveChainInspector.start do
        save_post_with_comment
      end
    end.to output(expected_output).to_stdout

    expect do
      save_post_with_comment
    end.not_to output.to_stdout
  end

  def save_post_with_comment
    post = Post.new
    post.comments.build
    post.save
  end
end
