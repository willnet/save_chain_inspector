# SaveChainInspector

When you execute save on a model in Active Record, the saves of related models with pre-set hooks are also executed. SaveChainInspector provides a way to know which models and which hooks have been executed specifically.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add save_chain_inspector --group=development,test

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install save_chain_inspector

## Usage

`SaveChainInspector.start` takes a block. It outputs the execution order of the save chain to the standard output.

```ruby      
SaveChainInspector.start do
  post = Post.new
  post.comments.build
  post.save
end
```

```
Post#save start
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
Post#save end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/willnet/save_chain_inspector. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/willnet/save_chain_inspector/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the SaveChainInspector project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/willnet/save_chain_inspector/blob/main/CODE_OF_CONDUCT.md).
