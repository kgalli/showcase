require File.expand_path('../spec_helper', __FILE__)

describe "OpenProject" do
  def app_name
    ENV.fetch('APP_NAME') { "openproject" }
  end

  def app_user
    ENV.fetch('APP_USER') { app_name }
  end

  def repo_url
    ENV.fetch('REPO_URL') { "https://deb.packager.io/gh/crohr/openproject" }
  end

  def launch_test(distribution, command, tag_val = nil)
    Instance.launch(distribution, tag_val) do |instance|
      instance.ssh(command) do |ssh|
        url = "https://#{instance.hostname}"
        puts url
        admin_password="admin"

        wait_until { ssh.exec!("ps -u #{app_user} -f").include?("unicorn worker") }
        ps_output = ssh.exec!("ps -u #{app_user} -f")
        expect(ps_output).to include("unicorn")

        # test check script
        check_output = ssh.exec!("sudo #{app_name} run check")
        puts check_output
        expect(check_output).to_not include("[ko]")

        # cold start
        system("curl -ks --retry 10 #{url}")

        # test redirection to HTTPS
        visit url.sub("https", "http")
        expect(page).to have_content("Sign in")

        # test sign in
        visit url
        expect(page).to have_content("Sign in")
        click_on "Sign in"
        fill_in "Login", with: "admin"
        fill_in "Password", with: "admin"
        click_button "Login"

        # does not work at the moment (server error in app/controllers/account_controller.rb:181:in `change_password')
        if branch == "dev"
          expect(page).to have_content("A new password is required")
          fill_in "Password", with: admin_password
          fill_in "New password", with: "1234p4ssw0rd"
          fill_in "Confirmation", with: "1234p4ssw0rd"
          click_button "Apply"
          admin_password = "1234p4ssw0rd"
        end

        expect(page).to have_content("OpenProject Admin")

        # load configuration
        click_on "Modules"
        # be specific, otherwise it would click on "Landing Page Administration" for instance
        find("a[title='Administration']").click
        expect(page).to have_content("Projects")
        if page.body.include?("Load the default configuration")
          click_button("Load the default configuration")
        end

        # create new project
        project_name = "hello-#{Time.now.to_i}"
        click_on("New project")
        fill_in "Name", with: project_name
        click_button "Save"
        expect(page).to have_content("Successful creation")

        # force cron to run earlier to create svn repo
        ssh.exec!("sudo sed -i 's|*/10|*|' /etc/cron.d/openproject-create-svn-repositories")
        sleep 70

        # check repository settings
        visit current_url
        within "#menu-sidebar" do
          click_link "Repository"
        end

        if page.body.include?("Subversion")
          # openproject-ee
          # FIXME once proper url is generated
          expect(find_field("checkout_url").value).to eq("file:///var/db/#{app_name}/svn/#{project_name}")
        else
          # openproject classic
          expect(page).to have_content("View all revisions")
        end

        # clone and commit a new file
        svn_args = "--trust-server-cert --non-interactive --username admin --password #{admin_password}"
        ssh.exec!(%{
cd /tmp && \
svn checkout #{svn_args} #{url}/svn/#{project_name} && \
cd #{project_name} && \
echo world > README.md && \
svn add README.md && \
svn ci #{svn_args} -m 'commit message'\
                  })

        visit current_url
        expect(page).to have_content("commit message")
        expect(page).to have_content("README.md")

        # Activity page makes use of Setting.host_name
        within "#menu-sidebar" do
          click_link "Activity"
        end
        expect(page).to have_content("Revision 1")
        expect(page).to have_content("commit message")

        # test backup script
        backup_output = ssh.exec!("sudo #{app_name} run backup 2>/dev/null")
        expect(backup_output).to include("/var/db/#{app_name}/backup/mysql-dump-")
        expect(backup_output).to include("/var/db/#{app_name}/backup/svn-repositories-")
        expect(backup_output).to include("/var/db/#{app_name}/backup/attachments-")
        expect(backup_output).to include("/var/db/#{app_name}/backup/conf-")
      end
    end
  end

  context "packaging branch" do
    distributions.each do |distribution|
      it "deploys OpenProject on #{distribution.name}, with new database" do
        template = Template.new(
          data_file("openproject/#{distribution.osfamily}/openproject-new-database.sh.erb"),
          codename: distribution.codename,
          branch: branch,
          repo_url: repo_url,
          app_name: app_name
        )
        command = Command.new(template.render, sudo: true, dry_run: dry_run?)
        launch_test(distribution, command, "#{distribution.name} - openproject new database")
      end

      it "deploys OpenProject on #{distribution.name}, with existing database" do
        template = Template.new(
          data_file("openproject/#{distribution.osfamily}/openproject-existing-database.sh.erb"),
          codename: distribution.codename,
          branch: branch,
          repo_url: repo_url,
          app_name: app_name
        )
        command = Command.new(template.render, sudo: true, dry_run: dry_run?)
        launch_test(distribution, command, "#{distribution.name} - openproject existing database")
      end
    end
  end
end
