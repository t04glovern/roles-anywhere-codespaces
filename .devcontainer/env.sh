#!/bin/bash

set -x
set -e

# Install openrolesanywhere client
if [ -e /tmp/openrolesanywhere ];
  then rm -rf /tmp/openrolesanywhere;
fi
git clone https://github.com/aidansteele/openrolesanywhere.git /tmp/openrolesanywhere
cd /tmp/openrolesanywhere/cmd/openrolesanywhere
go install .

if ([ -z "${ROLES_ANYWHERE_CERTIFICATE}" ] && [ -z "${ROLES_ANYWHERE_ROLE}" ] && [ -z "${SSH_PRIVATE_SIGNING_KEY}" ]); then
  echo "ROLES_ANYWHERE_CERTIFICATE, ROLES_ANYWHERE_ROLE or SSH_PRIVATE_SIGNING_KEY are undefined - skipping AWS auth setup within Codespaces"
else
  # Setup SSH Signing key
  mkdir -p ~/.ssh
  if [ -e ~/.ssh/id_rsa_codespaces ];
    then rm -rf ~/.ssh/id_rsa_codespaces;
  fi
  printenv 'SSH_PRIVATE_SIGNING_KEY' > ~/.ssh/id_rsa_codespaces
  chmod 400 ~/.ssh/id_rsa_codespaces
  ssh-keygen -y -f ~/.ssh/id_rsa_codespaces > ~/.ssh/id_rsa_codespaces.pub

  # Setup openrolesanywhere config
  mkdir -p ~/.config/openrolesanywhere
  printenv 'ROLES_ANYWHERE_CERTIFICATE' > ~/.config/openrolesanywhere/codespaces.pem

  # Create credential handler for AWS credential_process
  sudo tee /opt/roles-anywhere-handler << END
#!/bin/bash
eval "\$(ssh-agent -s)" > /dev/null
ssh-add ~/.ssh/id_rsa_codespaces > /dev/null
openrolesanywhere credential-process --name codespaces --role-arn $ROLES_ANYWHERE_ROLE
END

  # Setup AWS config
  mkdir -p ~/.aws
  tee ~/.aws/config << END
[profile default]
credential_process = /opt/roles-anywhere-handler
region = us-east-1
END
fi
