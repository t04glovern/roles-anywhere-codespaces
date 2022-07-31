# Roles Anywhere - Codespaces

This repository is setup to be used as a demo of AWS IAM Roles Anywhere without GitHub Codespaces.

It contains an example `.devcontainer` that will bootstrap the process of initialising your Codespace instances with a pre-authorized private key and AWS config that allows you to deploy/interact with AWS using AWS IAM Roles Anywhere.

This is very proof of concept, please don't use this in production.

## Deploy

First, we're going to use an AWS KMS asymmetric key as the private key for our certificate authority. Look at `kms.yml` for an example KMS key to create.

```bash
aws cloudformation deploy \
    --region us-east-1 \
    --template-file ./kms.yml \
    --stack-name openrolesanywhere-kms
```

Once you have the key ARN, we run the following command. It will create a new self-signed certificate (using the private key stored in KMS) and register it in Roles Anywhere as a trust anchor. 

The certificate will be stored in `~/.config/openrolesanywhere/ca.pem`.

```bash
KMS_KEY_ID=$(aws cloudformation describe-stacks \
    --stack-name "openrolesanywhere-kms" \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`KeyId`].OutputValue' \
    --output text)

openrolesanywhere admin create-ca \
    --name openrolesanywhere-trust \
    --kms-key-id $KMS_KEY_ID \
    --validity-duration 8760h \
    --serial-number 1 \
    --common-name Codespaces \
    --organization DevOpStar
```

Next, we create a profile. As best I can tell, this is a mapping from trust anchors to IAM roles.

```bash
aws cloudformation deploy \
    --region us-east-1 \
    --template-file ./role.yml \
    --stack-name openrolesanywhere-role \
    --capabilities CAPABILITY_IAM

# arn:aws:iam::012345678912:role/SomeRoleName
S3_EXAMPLE_ROLE=$(aws cloudformation describe-stacks \
    --stack-name "openrolesanywhere-role" \
    --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
    --output text)

openrolesanywhere admin create-profile \
    --name codespaces-example \
    --session-duration 3600s \
    --role-arn $S3_EXAMPLE_ROLE
```

Create a new SSH private key to use for this example

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
# Press ENTER a bunch
ssh-add ~/.ssh/id_rsa_codespaces
```

Run `ssh-add -l` to get a list of fingerprints for the keys stored in your SSH agent. Mine looks like this:

```bash
$ ssh-add -l
# 4096 SHA256:dxzQKbZvcaQkOpJ55YbZ+1/aWENrgBb8zZIkxl5BRGE your_email@example.com (RSA)
```

I want to use that second key, so I'll run the following command to generate a certificate request

```bash
openrolesanywhere request-certificate \
    --ssh-fingerprint SHA256:dxzQKbZvcaQkOpJ55YbZ+1/aWENrgBb8zZIkxl5BRGE > ./key.csr
```

Now we can send that CSR to our administrator (which is probably us in this example) and they will run the following command to generate a certicate for us to use with Roles Anywhere.

```bash
openrolesanywhere admin accept-request \
    --request-file ./key.csr \
    --validity-duration 8760h \
    --serial-number 2 \
    --common-name Codespaces \
    --organization DevOpStar > codespaces.pem
```

This creates a file called `codespaces.pem`, which is our public certificate. We tell the end-user (again, probably ourselves in this scenario) to store that file in `~/.config/openrolesanywhere/codespaces.pem`. 

Once they've done that, they can now configure the AWS CLI and SDKs to use it to retrieve AWS credentials. To do that, the end-user adds this to their `~/.aws/config`:

```bash
[profile default]
credential_process = eval $(keychain --eval --quiet id_rsa_codespaces) && openrolesanywhere credential-process --name codespaces --role-arn arn:aws:iam::012345678912:role/SomeRoleName
region = us-east-1
```

Now running `aws sts get-caller-identity` will work!

## Setup GitHub Codespace

Create the following GitHub repository secrets

```bash
ROLES_ANYWHERE_CERTIFICATE # Public certificate for Roles Anywhere
ROLES_ANYWHERE_ROLE # Role created for use in Codespaces
SSH_PRIVATE_SIGNING_KEY # SSH key that was used to sign requests to roles anywhere
```

When your codespace starts up, run any AWS commands you want

```bash
aws s3 ls
```
