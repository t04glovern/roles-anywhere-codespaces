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

Create a new SSH key to use for this example

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
# Press ENTER a bunch
ssh-add ~/.ssh/id_ed25519
```

Now we can start requesting certificates. First run `ssh-add -l` to get a list of fingerprints for the keys stored in your SSH agent. Mine looks like this:

```bash
$ ssh-add -l
# 256 SHA256:nxRD66QQrwlpcoSLie3NP1PdIwnUy4flj9Uh/wr023w your_email@example.com (ED25519)
```

I want to use that second key, so I'll run the following command:

```bash
openrolesanywhere request-certificate \
    --ssh-fingerprint SHA256:nxRD66QQrwlpcoSLie3NP1PdIwnUy4flj9Uh/wr023w > ./publickey.pem
```

Now we can send that to our administrator (which is probably us) and they will run:

```bash
openrolesanywhere admin accept-request \
    --request-file ./publickey.pem \
    --validity-duration 8760h \
    --serial-number 2 \
    --common-name Codespaces \
    --organization DevOpStar > codespaces.pem
```

This will create a file called `codespaces.pem`. We tell the end-user (again, probably ourselves) to store that file in `~/.config/openrolesanywhere/codespaces.pem`. 

Once they've done that, they can now configure the AWS CLI and SDKs to use it to retrieve AWS credentials. To do that, the end-user adds this to their `~/.aws/config`:

```bash
[profile default]
credential_process = openrolesanywhere credential-process --name codespaces --role-arn arn:aws:iam::012345678912:role/SomeRoleName
region = us-east-1
```

Now running `aws sts get-caller-identity` will work!
