module Bosh::Director
  module Jobs
    class UpdateDeployment < BaseJob
      include LockHelper
      include LegacyDeploymentHelper

      @queue = :normal

      def self.job_type
        :update_deployment
      end

      def initialize(manifest_text, cloud_config_id, runtime_config_ids, options = {})
        @blobstore = App.instance.blobstores.blobstore
        @manifest_text = manifest_text
        @cloud_config_id = cloud_config_id
        @runtime_config_ids = runtime_config_ids
        @options = options
        @event_log = Config.event_log
      end

      def dry_run?
        true if @options['dry_run']
      end

      def perform
        logger.info('Reading deployment manifest')
        manifest_hash = YAML.load(@manifest_text)
        logger.debug("Manifest:\n#{@manifest_text}")

        if ignore_cloud_config?(manifest_hash)
          warning = "Ignoring cloud config. Manifest contains 'networks' section."
          logger.debug(warning)
          @event_log.warn_deprecated(warning)
          cloud_config_model = nil
        else
          cloud_config_model = Bosh::Director::Models::CloudConfig[@cloud_config_id]
          if cloud_config_model.nil?
            logger.debug("No cloud config uploaded yet.")
          else
            logger.debug("Cloud config:\n#{cloud_config_model.raw_manifest}")
          end
        end

        runtime_config_models = Bosh::Director::Models::RuntimeConfig.find_by_ids(@runtime_config_ids)
        if runtime_config_models.empty?
          logger.debug("No runtime config uploaded yet.")
        else
          logger.debug("Runtime configs:\n#{Bosh::Director::RuntimeConfig::RuntimeConfigsConsolidator.new(runtime_config_models).raw_manifest}")
        end

        @deployment_name = manifest_hash['name']

        previous_releases, previous_stemcells = get_stemcells_and_releases
        context = {}
        parent_id = add_event
        is_deploy_action = @options['deploy']

        with_deployment_lock(@deployment_name) do
          deployment_plan = nil

          if is_deploy_action
            Bosh::Director::Models::Deployment.find(name: @deployment_name).add_variable_set(:created_at => Time.now, :writable => true)
          end

          deployment_manifest_object = Manifest.load_from_hash(manifest_hash, cloud_config_model, runtime_config_models)

          @notifier = DeploymentPlan::Notifier.new(@deployment_name, Config.nats_rpc, logger)
          @notifier.send_start_event unless dry_run?

          tmp_event_log = @event_log.begin_stage("NORTH POLE1: Trying to get lock for deployment #{@deployment_name}", 1)
          tmp_event_log.advance_and_track('NORTH POLE1: stage ') do
            puts 'hello from the north pole'
          end

          event_log_stage = @event_log.begin_stage('Preparing deployment', 1)
          event_log_stage.advance_and_track('Preparing deployment') do
            tmp_event_log = @event_log.begin_stage("NORTH POLE2: Trying to get lock for deployment #{@deployment_name}", 1)
            tmp_event_log.advance_and_track('NORTH POLE2: stage ') do
              puts 'hello from the north pole'
            end

            planner_factory = DeploymentPlan::PlannerFactory.create(logger)

            tmp_event_log = @event_log.begin_stage("NORTH POLE3: Trying to get lock for deployment #{@deployment_name}", 1)
            tmp_event_log.advance_and_track('NORTH POLE3: stage ') do
              puts 'hello from the north pole'
            end

            deployment_plan = planner_factory.create_from_manifest(deployment_manifest_object, cloud_config_model, runtime_config_models, @options)

            tmp_event_log = @event_log.begin_stage("NORTH POLE4: Trying to get lock for deployment #{@deployment_name}", 1)
            tmp_event_log.advance_and_track('NORTH POLE4: stage ') do
              puts 'hello from the north pole'
            end

            deployment_assembler = DeploymentPlan::Assembler.create(deployment_plan)

            tmp_event_log = @event_log.begin_stage("NORTH POLE5: Trying to get lock for deployment #{@deployment_name}", 1)
            tmp_event_log.advance_and_track('NORTH POLE5: stage ') do
              puts 'hello from the north pole'
            end

            generate_variables_values(deployment_plan.variables, @deployment_name) if is_deploy_action

            tmp_event_log = @event_log.begin_stage("NORTH POLE6: Trying to get lock for deployment #{@deployment_name}", 1)
            tmp_event_log.advance_and_track('NORTH POLE6: stage ') do
              puts 'hello from the north pole'
            end

            deployment_assembler.bind_models

            tmp_event_log = @event_log.begin_stage("NORTH POLE7: Trying to get lock for deployment #{@deployment_name}", 1)
            tmp_event_log.advance_and_track('NORTH POLE7: stage ') do
              puts 'hello from the north pole'
            end
          end

          if deployment_plan.instance_models.any?(&:ignore)
            @event_log.warn('You have ignored instances. They will not be changed.')
          end

          next_releases, next_stemcells = get_stemcells_and_releases
          context = event_context(next_releases, previous_releases, next_stemcells, previous_stemcells)

          tmp_event_log = @event_log.begin_stage("NORTH POLE8: Trying to get lock for deployment #{@deployment_name}", 1)
          tmp_event_log.advance_and_track('NORTH POLE8: stage ') do
            puts 'hello from the north pole'
          end

          begin
            current_variable_set = deployment_plan.model.current_variable_set

            tmp_event_log = @event_log.begin_stage("NORTH POLE9: Trying to get lock for deployment #{@deployment_name}", 1)
            tmp_event_log.advance_and_track('NORTH POLE9: stage ') do
              puts 'hello from the north pole'
            end

            if is_deploy_action
              update_instance_groups_variable_set(deployment_plan.instance_groups, current_variable_set)
            end

            render_templates_and_snapshot_errand_variables(deployment_plan, current_variable_set)

            if dry_run?
              return "/deployments/#{deployment_plan.name}"
            else
              tmp_event_log = @event_log.begin_stage("NORTH POLE10: Trying to get lock for deployment #{@deployment_name}", 1)
              tmp_event_log.advance_and_track('NORTH POLE10: stage ') do
                puts 'hello from the north pole'
              end

              compilation_step(deployment_plan).perform

              tmp_event_log = @event_log.begin_stage("NORTH POLE11: Trying to get lock for deployment #{@deployment_name}", 1)
              tmp_event_log.advance_and_track('NORTH POLE11: stage ') do
                puts 'hello from the north pole'
              end

              update_step(deployment_plan).perform

              tmp_event_log = @event_log.begin_stage("NORTH POLE12: Trying to get lock for deployment #{@deployment_name}", 1)
              tmp_event_log.advance_and_track('NORTH POLE12: stage ') do
                puts 'hello from the north pole'
              end

              if check_for_changes(deployment_plan)
                PostDeploymentScriptRunner.run_post_deploys_after_deployment(deployment_plan)
              end

              # only in the case of a deploy should you be cleaning up
              if is_deploy_action
                current_variable_set.update(deployed_successfully: true)
                remove_unused_variable_sets(deployment_plan.model, deployment_plan.instance_groups)
              end

              tmp_event_log = @event_log.begin_stage("NORTH POLE13: Trying to get lock for deployment #{@deployment_name}", 1)
              tmp_event_log.advance_and_track('NORTH POLE13: stage ') do
                puts 'hello from the north pole'
              end

              @notifier.send_end_event

              tmp_event_log = @event_log.begin_stage("NORTH POLE14: Trying to get lock for deployment #{@deployment_name}", 1)
              tmp_event_log.advance_and_track('NORTH POLE14: stage ') do
                puts 'hello from the north pole'
              end

              logger.info('Finished updating deployment')
              add_event(context, parent_id)

              "/deployments/#{deployment_plan.name}"
            end
          ensure
            deployment_plan.job_renderer.clean_cache!
          end
        end
      rescue Exception => e
        begin
          @notifier.send_error_event e unless dry_run?
        rescue Exception => e2
          # log the second error
        ensure
          add_event(context, parent_id, e)
          raise e
        end
      ensure
        if @options['deploy']
          deployment = current_deployment
          variable_set = deployment == nil ? nil : deployment.current_variable_set
          if variable_set
            variable_set.update(:writable => false)
          end
        end
      end

      private

      def update_instance_groups_variable_set(instance_groups, current_variable_set)
        instance_groups.each do |instance_group|
          instance_group.assign_variable_set(current_variable_set)
        end
      end

      def remove_unused_variable_sets(deployment, instance_groups)
        variable_sets_to_keep = []
        variable_sets_to_keep << deployment.current_variable_set
        instance_groups.each do |instance_group|
          variable_sets_to_keep += instance_group.referenced_variable_sets
        end

        deployment.cleanup_variable_sets(variable_sets_to_keep.uniq)
      end

      def add_event(context = {}, parent_id = nil, error = nil)
        action = @options.fetch('new', false) ? "create" : "update"
        event = event_manager.create_event(
          {
            parent_id: parent_id,
            user: username,
            action: action,
            object_type: "deployment",
            object_name: @deployment_name,
            deployment: @deployment_name,
            task: task_id,
            error: error,
            context: context
          })
        event.id
      end

      # Job tasks

      def check_for_changes(deployment_plan)
        deployment_plan.instance_groups.each do |job|
          return true if job.did_change
        end
        false
      end

      def compilation_step(deployment_plan)
        DeploymentPlan::Steps::PackageCompileStep.create(deployment_plan)
      end

      def update_step(deployment_plan)
        DeploymentPlan::Steps::UpdateStep.new(
          self,
          deployment_plan,
          multi_job_updater(deployment_plan)
        )
      end

      # Job dependencies

      def multi_job_updater(deployment_plan)
        @multi_job_updater ||= begin
          DeploymentPlan::BatchMultiJobUpdater.new(JobUpdaterFactory.new(logger, deployment_plan.job_renderer))
        end
      end

      def render_templates_and_snapshot_errand_variables(deployment_plan, current_variable_set)
        errors = render_instance_groups_templates(deployment_plan.instance_groups_starting_on_deploy, deployment_plan.job_renderer)
        errors += snapshot_errands_variables_versions(deployment_plan.errand_instance_groups, current_variable_set)

        unless errors.empty?
          message = errors.map { |error| error.message.strip }.join("\n")
          header = 'Unable to render instance groups for deployment. Errors are:'
          raise Bosh::Director::FormatterHelper.new.prepend_header_and_indent_body(header, message, {:indent_by => 2})
        end
      end

      def render_instance_groups_templates(instance_groups, job_renderer)
        errors = []
        instance_groups.each do |instance_group|
          begin
            job_renderer.render_job_instances(instance_group.unignored_instance_plans)
          rescue Exception => e
            errors.push e
          end
        end
        errors
      end

      def snapshot_errands_variables_versions(errands_instance_groups, current_variable_set)
        errors = []
        variables_interpolator = ConfigServer::VariablesInterpolator.new

        errands_instance_groups.each do |instance_group|
          instance_group_errors = []

          begin
            variables_interpolator.interpolate_template_spec_properties(instance_group.properties, @deployment_name, current_variable_set)
          rescue Exception => e
            instance_group_errors.push e
          end

          begin
            variables_interpolator.interpolate_link_spec_properties(instance_group.resolved_links || {}, current_variable_set)
          rescue Exception => e
            instance_group_errors.push e
          end

          unless instance_group_errors.empty?
            message = instance_group_errors.map { |error| error.message.strip }.join("\n")
            header = "- Unable to render jobs for instance group '#{instance_group.name}'. Errors are:"
            e = Exception.new(Bosh::Director::FormatterHelper.new.prepend_header_and_indent_body(header, message, {:indent_by => 2}))
            errors << e
          end
        end
        errors
      end

      def get_stemcells_and_releases
        deployment = current_deployment
        stemcells = []
        releases = []
        if deployment
          releases = deployment.release_versions.map do |rv|
            "#{rv.release.name}/#{rv.version}"
          end
          stemcells = deployment.stemcells.map do |sc|
            "#{sc.name}/#{sc.version}"
          end
        end
        return releases, stemcells
      end

      def current_deployment
        Models::Deployment[name: @deployment_name]
      end

      def event_context(next_releases, previous_releases, next_stemcells, previous_stemcells)
        after_objects = {}
        after_objects['releases'] = next_releases unless next_releases.empty?
        after_objects['stemcells'] = next_stemcells unless next_stemcells.empty?

        before_objects = {}
        before_objects['releases'] = previous_releases unless previous_releases.empty?
        before_objects['stemcells'] = previous_stemcells unless previous_stemcells.empty?

        context = {}
        context['before'] = before_objects
        context['after'] = after_objects
        context
      end

      def generate_variables_values(variables, deployment_name)
        config_server_client = Bosh::Director::ConfigServer::ClientFactory.create(@logger).create_client
        config_server_client.generate_values(variables, deployment_name)
      end
    end
  end
end
