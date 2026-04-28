.PHONY: shutdown shutdown-dry-run sync feature-push pr merge

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
	# Prune merged branches from Gitea
	git remote prune gitea
	git remote prune origin

# Create PRs on both GH and Gitea
pr: feature-push
	@BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	TITLE=$$(git log -1 --pretty=%s); \
	BODY=$$(git log -1 --pretty=%b); \
	echo "Creating GitHub PR..."; \
	gh pr create --title "$$TITLE" --body "$$BODY" || echo "GH PR already exists"; \
	echo "Creating Gitea PR..."; \
	GITEA_USER=$$(grep "gitea_admin_username:" group_vars/all.yml | awk '{print $$2}'); \
	GITEA_PASS=$$(grep "gitea_admin_password:" group_vars/all.yml | awk '{print $$2}'); \
	curl -s -X 'POST' \
	  'https://gitea.fleet1.lan/api/v1/repos/gitadmin/vanlab/pulls' \
	  -H 'accept: application/json' \
	  -u "$$GITEA_USER:$$GITEA_PASS" \
	  -H 'Content-Type: application/json' \
	  -d "{ \
	  \"base\": \"main\", \
	  \"body\": \"$$BODY\", \
	  \"head\": \"$$BRANCH\", \
	  \"title\": \"$$TITLE\" \
	}" | grep -q "id" && echo "Gitea PR created." || echo "Gitea PR already exists or failed."; \
	echo "\nPRs created successfully."

# Merge PRs on both GH and Gitea
merge:
	@BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$BRANCH" = "main" ]; then \
		echo "Error: Cannot merge from main."; \
		exit 1; \
	fi; \
	echo "Merging GitHub PR..."; \
	gh pr merge --admin --merge --delete-branch || echo "GH PR merge failed or already merged"; \
	echo "Merging Gitea PR..."; \
	GITEA_USER=$$(grep "gitea_admin_username:" group_vars/all.yml | awk '{print $$2}'); \
	GITEA_PASS=$$(grep "gitea_admin_password:" group_vars/all.yml | awk '{print $$2}'); \
	PR_INDEX=$$(curl -s -u "$$GITEA_USER:$$GITEA_PASS" "https://gitea.fleet1.lan/api/v1/repos/gitadmin/vanlab/pulls?state=open" | jq -r ".[] | select(.head.label == \"$$BRANCH\") | .number"); \
	if [ -n "$$PR_INDEX" ] && [ "$$PR_INDEX" != "null" ]; then \
		curl -s -X 'POST' \
		  "https://gitea.fleet1.lan/api/v1/repos/gitadmin/vanlab/pulls/$$PR_INDEX/merge" \
		  -H 'accept: application/json' \
		  -u "$$GITEA_USER:$$GITEA_PASS" \
		  -H 'Content-Type: application/json' \
		  -d '{ \
		  "Do": "merge", \
		  "delete_branch_after_merge": true \
		}' && echo "Gitea PR merged."; \
	else \
		echo "Gitea PR not found or already merged."; \
	fi; \
	$(MAKE) sync
