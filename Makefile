.PHONY: shutdown shutdown-dry-run sync feature-push

shutdown:
	ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml

shutdown-dry-run:
	ansible-playbook -i hosts.ini playbooks/utilities/rack-shutdown.yml --check

# Push the current branch to both GH and Gitea to prepare for dual PRs
feature-push:
	@BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$BRANCH" = "main" ]; then \
		echo "Error: Cannot feature-push from main. Use a feature branch."; \
		exit 1; \
	fi; \
	git push origin $$BRANCH; \
	git push gitea $$BRANCH

# Sync main from GitHub and prune merged branches locally and on remotes
sync:
	git checkout main
	git pull origin main
	git fetch --all --prune
	# Prune local branches merged into main
	git branch --merged main | grep -v '^\*\|  main' | xargs -r git branch -d
	# Prune merged branches from Gitea (since we can't push to main, we clean up the feature branches)
	git remote prune gitea
	git remote prune origin
