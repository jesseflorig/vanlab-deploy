.PHONY: shutdown shutdown-dry-run sync

shutdown:
	ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml

shutdown-dry-run:
	ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml --check

sync:
	git checkout main
	git pull origin main
	git push gitea main
	git fetch --all --prune
	# Prune local branches that have been merged into main (excluding main itself)
	git branch --merged main | grep -v '^\*\|  main' | xargs -r git branch -d
