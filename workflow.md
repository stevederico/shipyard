1. If NEW_PROJECT is true, scaffold the project from scratch (create README, package.json, etc.)
2. Implement the task
3. Run tests if they exist
4. If tests fail, fix and re-run (max 3 attempts)
5. Stage only the files you modified (never git add . or git add -A)
6. Commit with a descriptive message (no AI attribution, no Co-Authored-By)
7. If NEW_PROJECT is true, create a GitHub repo: gh repo create PROJECT --private --source=. --push
8. Push the branch: git push origin BRANCH
9. If NEW_PROJECT is false, open a PR: gh pr create --base BASE_BRANCH
10. Print FACTORY_RESULT:SUCCESS or FACTORY_RESULT:FAILED
