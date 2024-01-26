require 'spec_helper'
require 'r10k/module_loader/puppetfile'
require 'tmpdir'

describe R10K::ModuleLoader::Puppetfile do
  describe 'initial parameters' do
    describe 'honor' do
      let(:options) do
        {
          basedir: '/test/basedir/env',
          overrides: { modules: { deploy_modules: true } },
          environment: R10K::Environment::Git.new('env',
                                                  '/test/basedir/',
                                                  'env',
                                                  { remote: 'https://foo/remote',
                                                    ref: 'env' })
        }
      end

      subject { R10K::ModuleLoader::Puppetfile.new(**options) }

      describe 'the moduledir' do
        it 'respects absolute paths' do
          absolute_options = options.merge({moduledir: '/opt/puppetlabs/special/modules'})
          puppetfile = R10K::ModuleLoader::Puppetfile.new(**absolute_options)
          expect(puppetfile.instance_variable_get(:@moduledir)).to eq('/opt/puppetlabs/special/modules')
        end

        it 'roots the moduledir in the basepath if a relative path is specified' do
          relative_options = options.merge({moduledir: 'my/special/modules'})
          puppetfile = R10K::ModuleLoader::Puppetfile.new(**relative_options)
          expect(puppetfile.instance_variable_get(:@moduledir)).to eq('/test/basedir/env/my/special/modules')
        end
      end

      describe 'the Puppetfile' do
        it 'respects absolute paths' do
          absolute_options = options.merge({puppetfile: '/opt/puppetlabs/special/Puppetfile'})
          puppetfile = R10K::ModuleLoader::Puppetfile.new(**absolute_options)
          expect(puppetfile.instance_variable_get(:@puppetfile_path)).to eq('/opt/puppetlabs/special/Puppetfile')
        end

        it 'roots the Puppetfile in the basepath if a relative path is specified' do
          relative_options = options.merge({puppetfile: 'Puppetfile.global'})
          puppetfile = R10K::ModuleLoader::Puppetfile.new(**relative_options)
          expect(puppetfile.instance_variable_get(:@puppetfile_path)).to eq('/test/basedir/env/Puppetfile.global')
        end
      end

      it 'the overrides' do
        expect(subject.instance_variable_get(:@overrides)).to eq({ modules: { deploy_modules: true }})
      end

      it 'the environment' do
        expect(subject.instance_variable_get(:@environment).name).to eq('env')
      end
    end

    describe 'sane defaults' do
      subject { R10K::ModuleLoader::Puppetfile.new(basedir: '/test/basedir') }

      it 'has a moduledir rooted in the basedir' do
        expect(subject.instance_variable_get(:@moduledir)).to eq('/test/basedir/modules')
      end

      it 'has a Puppetfile rooted in the basedir' do
        expect(subject.instance_variable_get(:@puppetfile_path)).to eq('/test/basedir/Puppetfile')
      end

      it 'creates an empty overrides' do
        expect(subject.instance_variable_get(:@overrides)).to eq({})
      end

      it 'does not require an environment' do
        expect(subject.instance_variable_get(:@environment)).to eq(nil)
      end
    end
  end

  describe 'adding modules' do
    let(:basedir) { '/test/basedir' }

    subject { R10K::ModuleLoader::Puppetfile.new(basedir: basedir,
                                                 overrides: {modules: {exclude_spec: false}}) }

    it 'should transform Forge modules with a string arg to have a version key' do
      expect(R10K::Module).to receive(:from_metadata).with('puppet/test_module', subject.moduledir, hash_including(version: '1.2.3'), anything).and_call_original

      expect { subject.add_module('puppet/test_module', '1.2.3') }.to change { subject.modules }
      expect(subject.modules.collect(&:name)).to include('test_module')
    end

    it 'should not accept Forge modules with a version comparison' do
      expect(R10K::Module).to receive(:from_metadata).with('puppet/test_module', subject.moduledir, hash_including(version: '< 1.2.0'), anything).and_call_original

      expect {
        subject.add_module('puppet/test_module', '< 1.2.0')
      }.to raise_error(ArgumentError, /module version .* is not a valid forge module version/i)

      expect(subject.modules.collect(&:name)).not_to include('test_module')
    end

    it 'should not modify the overrides when adding modules' do
      module_opts = { git: 'git@example.com:puppet/test_module.git' }
      subject.add_module('puppet/test_module', module_opts)
      expect(subject.instance_variable_get("@overrides")[:modules]).to eq({exclude_spec: false})
    end

    it 'should read the `exclude_spec` setting in the module definition and override the overrides' do
      module_opts = { git: 'git@example.com:puppet/test_module.git', exclude_spec: true }
      subject.add_module('puppet/test_module', module_opts)
      expect(subject.modules[0].instance_variable_get("@exclude_spec")).to be true
    end

    it 'should set :spec_deletable to true for modules in the basedir' do
      module_opts = { git: 'git@example.com:puppet/test_module.git' }
      subject.add_module('puppet/test_module', module_opts)
      expect(subject.modules[0].spec_deletable).to be true
    end

    it 'should set :spec_deletable to false for modules outside the basedir' do
      module_opts = { git: 'git@example.com:puppet/test_module.git', install_path: 'some/path' }
      subject.add_module('puppet/test_module', module_opts)
      expect(subject.modules[0].spec_deletable).to be false
    end

    it 'should accept non-Forge modules with a hash arg' do
      module_opts = { git: 'git@example.com:puppet/test_module.git' }

      expect(R10K::Module).to receive(:from_metadata).with('puppet/test_module', subject.moduledir, module_opts, anything).and_call_original

      expect { subject.add_module('puppet/test_module', module_opts) }.to change { subject.modules }
      expect(subject.modules.collect(&:name)).to include('test_module')
    end

    it 'should accept non-Forge modules with a valid relative :install_path option' do
      module_opts = {
        install_path: 'vendor',
        git: 'git@example.com:puppet/test_module.git',
      }

      expect(R10K::Module).to receive(:from_metadata).with('puppet/test_module', File.join(basedir, 'vendor'), module_opts, anything).and_call_original

      expect { subject.add_module('puppet/test_module', module_opts) }.to change { subject.modules }
      expect(subject.modules.collect(&:name)).to include('test_module')
    end

    it 'should accept non-Forge modules with a valid absolute :install_path option' do
      install_path = File.join(basedir, 'vendor')

      module_opts = {
        install_path: install_path,
        git: 'git@example.com:puppet/test_module.git',
      }

      expect(R10K::Module).to receive(:from_metadata).with('puppet/test_module', install_path, module_opts, anything).and_call_original

      expect { subject.add_module('puppet/test_module', module_opts) }.to change { subject.modules }
      expect(subject.modules.collect(&:name)).to include('test_module')
    end

    it 'should reject non-Forge modules with an invalid relative :install_path option' do
      module_opts = {
        install_path: '../../vendor',
        git: 'git@example.com:puppet/test_module.git',
      }

      expect { subject.add_module('puppet/test_module', module_opts) }.to raise_error(R10K::Error, /cannot manage content.*is not within/i).and not_change { subject.modules }
    end

    it 'should reject non-Forge modules with an invalid absolute :install_path option' do
      module_opts = {
        install_path: '/tmp/mydata/vendor',
        git: 'git@example.com:puppet/test_module.git',
      }

      expect { subject.add_module('puppet/test_module', module_opts) }.to raise_error(R10K::Error, /cannot manage content.*is not within/i).and not_change { subject.modules }
    end

    it 'should disable and not add modules that conflict with the environment' do
      env = instance_double('R10K::Environment::Base')
      mod = instance_double('R10K::Module::Base', name: 'conflict', origin: :puppetfile, 'origin=': nil)
      allow(env).to receive(:name).and_return('conflict')
      loader = R10K::ModuleLoader::Puppetfile.new(basedir: basedir, environment: env)
      allow(env).to receive(:'module_conflicts?').with(mod).and_return(true)
      allow(mod).to receive(:spec_deletable=)

      expect(R10K::Module).to receive(:from_metadata).with('conflict', anything, anything, anything).and_return(mod)
      expect { loader.add_module('conflict', {}) }.not_to change { loader.modules }
    end
  end

  describe '#purge_exclusions' do
    let(:managed_dirs) { ['dir1', 'dir2'] }
    subject { R10K::ModuleLoader::Puppetfile.new(basedir: '/test/basedir') }

    it 'includes managed_directories' do
      expect(subject.send(:determine_purge_exclusions, managed_dirs)).to match_array(managed_dirs)
    end

    context 'when belonging to an environment' do
      let(:env_contents) { ['env1', 'env2' ] }
      let(:env) { double(:environment, desired_contents: env_contents) }
      before {
        allow(env).to receive(:name).and_return('env1')
      }
      subject { R10K::ModuleLoader::Puppetfile.new(basedir: '/test/basedir', environment: env) }

      it "includes environment's desired_contents" do
        expect(subject.send(:determine_purge_exclusions, managed_dirs)).to match_array(managed_dirs + env_contents)
      end
    end
  end

  describe '#managed_directories' do

    let(:basedir) { '/test/basedir' }
    subject { R10K::ModuleLoader::Puppetfile.new(basedir: basedir) }

    before do
      allow(subject).to receive(:puppetfile_content).and_return('')
    end

    it 'returns an array of paths that #purge! will operate within' do
      expect(R10K::Module).to receive(:from_metadata).with('puppet/test_module', subject.moduledir, hash_including(version: '1.2.3'), anything).and_call_original
      subject.add_module('puppet/test_module', '1.2.3')
      subject.load!

      expect(subject.modules.length).to be 1
      expect(subject.managed_directories).to match_array([subject.moduledir])
    end

    context "with a module with install_path == ''" do
      it "basedir isn't in the list of paths to purge" do
        module_opts = { install_path: '', git: 'git@example.com:puppet/test_module.git' }

        expect(R10K::Module).to receive(:from_metadata).with('puppet/test_module', basedir, module_opts, anything).and_call_original
        subject.add_module('puppet/test_module', module_opts)
        subject.load!

        expect(subject.modules.length).to be 1
        expect(subject.managed_directories).to be_empty
      end
    end
  end

  describe 'evaluating a Puppetfile' do
    def expect_wrapped_error(error, pf_path, error_type)
      expect(error).to be_a_kind_of(R10K::Error)
      expect(error.message).to eq("Failed to evaluate #{pf_path}")
      expect(error.original).to be_a_kind_of(error_type)
    end

    subject { described_class.new(basedir: @path) }

    it 'wraps and re-raises syntax errors' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'invalid-syntax')
      pf_path = File.join(@path, 'Puppetfile')
      expect {
        subject.load!
      }.to raise_error do |e|
        expect_wrapped_error(e, pf_path, SyntaxError)
      end
    end

    it 'wraps and re-raises load errors' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'load-error')
      pf_path = File.join(@path, 'Puppetfile')
      expect {
        subject.load!
      }.to raise_error do |e|
        expect_wrapped_error(e, pf_path, LoadError)
      end
    end

    it 'wraps and re-raises argument errors' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'argument-error')
      pf_path = File.join(@path, 'Puppetfile')
      expect {
        subject.load!
      }.to raise_error do |e|
        expect_wrapped_error(e, pf_path, ArgumentError)
      end
    end

    describe 'forge declaration' do
      before(:each) do
        PuppetForge.host = ""
      end

      it 'is respected if `allow_puppetfile_override` is true' do
        @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'forge-override')
        puppetfile = R10K::ModuleLoader::Puppetfile.new(basedir: @path, overrides: { forge: { allow_puppetfile_override: true } })
        puppetfile.load!
        expect(PuppetForge.host).to eq("my.custom.forge.com/")
      end

      it 'is ignored if `allow_puppetfile_override` is false' do
        @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'forge-override')
        puppetfile = R10K::ModuleLoader::Puppetfile.new(basedir: @path, overrides: { forge: { allow_puppetfile_override: false } })
        expect(PuppetForge).not_to receive(:host=).with("my.custom.forge.com")
        puppetfile.load!
        expect(PuppetForge.host).to eq("/")
      end
    end

    it 'rejects Puppetfiles with duplicate module names' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'duplicate-module-error')
      pf_path = File.join(@path, 'Puppetfile')
      expect {
        subject.load!
      }.to raise_error(R10K::Error, /Puppetfiles cannot contain duplicate module names/i)
    end

    it 'wraps and re-raises name errors' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'name-error')
      pf_path = File.join(@path, 'Puppetfile')
      expect {
        subject.load!
      }.to raise_error do |e|
        expect_wrapped_error(e, pf_path, NameError)
      end
    end

    it 'accepts a forge module with a version' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'valid-forge-with-version')
      pf_path = File.join(@path, 'Puppetfile')
      expect { subject.load! }.not_to raise_error
    end

    describe 'setting a custom moduledir' do
      it 'allows setting an absolute moduledir' do
        @path = '/fake/basedir'
        allow(subject).to receive(:puppetfile_content).and_return('moduledir "/fake/moduledir"')
        subject.load!
        expect(subject.instance_variable_get(:@moduledir)).to eq('/fake/moduledir')
      end

      it 'roots relative moduledirs in the basedir' do
        @path = '/fake/basedir'
        allow(subject).to receive(:puppetfile_content).and_return('moduledir "my/moduledir"')
        subject.load!
        expect(subject.instance_variable_get(:@moduledir)).to eq(File.join(@path, 'my/moduledir'))
      end
    end

    it 'accepts a forge module without a version' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'valid-forge-without-version')
      pf_path = File.join(@path, 'Puppetfile')
      expect { subject.load! }.not_to raise_error
    end

    it 'creates a git module and applies the default branch specified in the Puppetfile' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'default-branch-override')
      pf_path = File.join(@path, 'Puppetfile')
      expect { subject.load! }.not_to raise_error
      git_module = subject.modules[0]
      expect(git_module.default_ref).to eq 'here_lies_the_default_branch'
    end

    it 'creates a git module and applies the provided default_branch_override' do
      @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'default-branch-override')
      pf_path = File.join(@path, 'Puppetfile')
      default_branch_override = 'default_branch_override_name'
      subject.default_branch_override = default_branch_override
      expect { subject.load! }.not_to raise_error
      git_module = subject.modules[0]
      expect(git_module.default_override_ref).to eq default_branch_override
      expect(git_module.default_ref).to eq 'here_lies_the_default_branch'
    end

    describe 'using module metadata' do
      it 'properly loads module metadata' do
        @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'various-modules')
        metadata = subject.load_metadata[:modules].map { |mod| [ mod.name, mod.version ] }.to_h
        expect(metadata['apt']).to eq('2.1.1')
        expect(metadata['stdlib']).to eq(nil)
        expect(metadata['concat']).to eq(nil)
        expect(metadata['rpm']).to eq('2.1.1-pre1')
        expect(metadata['foo']).to eq(nil)
        expect(metadata['bar']).to eq('v1.2.3')
        expect(metadata['baz']).to eq('123abc456')
        expect(metadata['fizz']).to eq('1234567890abcdef1234567890abcdef12345678')
        expect(metadata['buzz']).to eq(nil)
        expect(metadata['canary']).to eq('0.0.0')
      end

      it 'does not load module implementations for static versions unless the module install path does not exist on disk' do
        @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'various-modules')
        subject.load_metadata
        modules = subject.load[:modules].map { |mod| [ mod.name, mod ] }.to_h
        expect(modules['apt']).to be_a_kind_of(R10K::Module::Definition)
        expect(modules['stdlib']).to be_a_kind_of(R10K::Module::Forge)
        expect(modules['concat']).to be_a_kind_of(R10K::Module::Forge)
        expect(modules['rpm']).to be_a_kind_of(R10K::Module::Definition)
        expect(modules['foo']).to be_a_kind_of(R10K::Module::Git)
        expect(modules['bar']).to be_a_kind_of(R10K::Module::Git)
        expect(modules['baz']).to be_a_kind_of(R10K::Module::Definition)
        expect(modules['fizz']).to be_a_kind_of(R10K::Module::Definition)
        expect(modules['buzz']).to be_a_kind_of(R10K::Module::Git)
        expect(modules['canary']).to be_a_kind_of(R10K::Module::Definition)
      end

      it 'loads module implementations whose static versions are different' do
        fixture_path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'various-modules')
        @path = Dir.mktmpdir
        unsynced_pf_path = File.join(fixture_path, 'Puppetfile')
        FileUtils.cp(unsynced_pf_path, @path)

        subject.load_metadata

        synced_pf_path = File.join(fixture_path, 'Puppetfile.new')
        FileUtils.cp(synced_pf_path, File.join(@path, 'Puppetfile'))

        modules = subject.load[:modules].map { |mod| [ mod.name, mod ] }.to_h

        expect(modules['apt']).to be_a_kind_of(R10K::Module::Forge)
      end

    end

    describe 'using module-exclude-regex' do
      it 'can exclude a module from being installed' do
        @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'various-modules')
        puppetfile = R10K::ModuleLoader::Puppetfile.new(basedir: @path, module_exclude_regex: '^concat$')
        puppetfile.load!
        expect(puppetfile.modules.collect(&:name)).not_to include('concat')
      end

      it 'can exclude multiple modules from being installed' do
        @path = File.join(PROJECT_ROOT, 'spec', 'fixtures', 'unit', 'puppetfile', 'various-modules')
        puppetfile = R10K::ModuleLoader::Puppetfile.new(basedir: @path, module_exclude_regex: '^ba[rz]$')
        puppetfile.load!
        expect(puppetfile.modules.collect(&:name)).not_to include('bar')
        expect(puppetfile.modules.collect(&:name)).not_to include('baz')
      end
    end
  end
end
