# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SaveChainInspector do
  it 'write logs inside the block' do
    expect do
      SaveChainInspector.start do
        post = Post.new
        post.comments.build
        post.save
      end
    end.to output(<<~OUTPUT).to_stdout
      Post#save start
        Post#before_save start
        Post#before_save end
        Post#after_create start
          Post#autosave_associated_records_for_comments start
            Comment#save start
              Comment#before_save start
                Comment#autosave_associated_records_for_post start
                Comment#autosave_associated_records_for_post end
              Comment#before_save end
              Comment#after_create start
              Comment#after_create end
            Comment#save end
          Post#autosave_associated_records_for_comments end
        Post#after_create end
      Post#save end
    OUTPUT
  end

  it "doesn't write logs outside the block" do
    SaveChainInspector.start do
      post = Post.new
      post.comments.build
      post.save
    end
    expect do
      post = Post.new
      post.comments.build
      post.save
    end.not_to output.to_stdout
  end
end
