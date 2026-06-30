# frozen_string_literal: true

require 'stringio'
require 'tmpdir'

require 'spec_helper'

RSpec.describe SaveChainInspector do
  let(:expected_output) do
    <<~OUTPUT
      Post#save start
        Post#before_save start/end
        Post#after_create start
          Post#autosave_associated_records_for_comments start
            Comment#save start
              Comment#before_save start
                Comment#autosave_associated_records_for_post start/end
              Comment#before_save end
              Comment#after_create start/end
            Comment#save end
          Post#autosave_associated_records_for_comments end
        Post#after_create end
      Post#save end
    OUTPUT
  end

  it 'write logs inside the block' do
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
