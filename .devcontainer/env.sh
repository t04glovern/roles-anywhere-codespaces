#!/bin/bash

set -x
set -e

# Install openrolesanywhere client
git clone https://github.com/aidansteele/openrolesanywhere.git /tmp/openrolesanywhere
cd /tmp/openrolesanywhere/cmd/openrolesanywhere
go install .

if ([ -z "${ROLES_ANYWHERE_PRIVATE_KEY}" ] && [ -z "${ROLES_ANYWHERE_ROLE}" ] && [ -z "${SSH_SIGNING_KEY}" ]); then
  echo "ROLES_ANYWHERE_PRIVATE_KEY, ROLES_ANYWHERE_ROLE or SSH_SIGNING_KEY are undefined - skipping AWS auth setup within Codespaces"
else
  # Setup SSH Signing key
  mkdir -p ~/.ssh
  printenv 'SSH_SIGNING_KEY' > ~/.ssh/id_ed25519
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/id_ed25519

  # Setup openrolesanywhere config
  mkdir -p ~/.config/openrolesanywhere
  printenv 'ROLES_ANYWHERE_PRIVATE_KEY' > ~/.config/openrolesanywhere/codespaces.pem

  # Setup AWS config
  mkdir -p ~/.aws
  tee -a ~/.aws/config << END
[profile default]
credential_process = openrolesanywhere credential-process --name codespaces --role-arn $ROLES_ANYWHERE_ROLE
region = us-east-1
END
fi
