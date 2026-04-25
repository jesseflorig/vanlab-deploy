.PHONY: shutdown shutdown-dry-run

shutdown:
	ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml

shutdown-dry-run:
	ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml --check
