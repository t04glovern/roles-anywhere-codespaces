# Roles Anywhere - Codespaces

## Install

```bash
wget -O /tmp/go1.18.4.linux-amd64.tar.gz https://go.dev/dl/go1.18.4.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf /tmp/go1.18.4.linux-amd64.tar.gz

git clone https://github.com/aidansteele/openrolesanywhere.git && cd openrolesanywhere/cmd/openrolesanywhere
go install .
```

## Deploy

First, we're going to use an AWS KMS asymmetric key as the private key for our certificate authority. Look at `kms.yml` for an example KMS key to create.

```bash
aws cloudformation deploy \
    --template-file ./kms.yml \
    --stack-name openrolesanywhere-kms
```

Once you have the key ARN, we run the following command. It will create a new self-signed certificate (using the private key stored in KMS) and register it in Roles Anywhere as a trust anchor. 

The certificate will be stored in `~/.config/openrolesanywhere/ca.pem`.

```bash
KMS_KEY_ID=$(aws cloudformation describe-stacks \
    --stack-name "openrolesanywhere-kms" \
    --query 'Stacks[0].Outputs[?OutputKey==`KeyId`].OutputValue' \
    --output text)

openrolesanywhere admin create-ca \
    --name openrolesanywhere-trust \
    --kms-key-id $KMS_KEY_ID \
    --validity-duration 8760h \
    --serial-number 1 \
    --common-name openrolesanywhere
```

Next, we create a profile. As best I can tell, this is a mapping from trust anchors to IAM roles.

```bash
aws cloudformation deploy \
    --template-file ./role.yml \
    --stack-name openrolesanywhere-role \
    --capabilities CAPABILITY_IAM

# arn:aws:iam::012345678912:role/SomeRoleName
S3_EXAMPLE_ROLE=$(aws cloudformation describe-stacks \
    --stack-name "openrolesanywhere-role" \
    --query 'Stacks[0].Outputs[?OutputKey==`RoleExampleArn`].OutputValue' \
    --output text)

openrolesanywhere admin create-profile \
    --name openrolesanywhere-s3-role \
    --session-duration 3600s \
    --role-arn $S3_EXAMPLE_ROLE
```

Now we can start requesting certificates. First run ssh-add -l to get a list of fingerprints for the keys stored in your SSH agent. Mine looks like this:

```bash
256 SHA256:KBsk40KWP/UDoYoiFnpFk+z5JnMInwsrAFONMLrlryc ecdsa-sha2-nistp256 (ECDSA)
256 SHA256:z/A9nNwdk1ZTmwtdrAlF2JQnGS8C7V3ozOPMt5lgqBk ecdsa-sha2-nistp256 (ECDSA)
```

I want to use that second key, so I'll run the following command:

```bash
openrolesanywhere request-certificate \
    --ssh-fingerprint SHA256:z/A9nNwdk1ZTmwtdrAlF2JQnGS8C7V3ozOPMt5lgqBk > ./publickey.pem
```

Now we can send that to our administrator (which is probably us) and they will run:

```bash
AWS_COMMON_NAME="john-doe"

openrolesanywhere admin accept-request \
  --request-file ./publickey.pem \
  --validity-duration 8760h \
  --serial-number 2 \
  --common-name $AWS_COMMON_NAME > ./$AWS_COMMON_NAME.pem
```

This will create a file called `$AWS_COMMON_NAME.pem`. We tell the end-user (again, probably ourselves) to store that file in `~/.config/openrolesanywhere/john-doe.pem`. 

Once they've done that, they can now configure the AWS CLI and SDKs to use it to retrieve AWS credentials. To do that, the end-user adds this to their `~/.aws/config`:

```bash
[profile john-doe]
credential_process = openrolesanywhere credential-process --name john-doe --role-arn arn:aws:iam::012345678912:role/SomeRoleName
region = us-west-2
```

Now running `aws sts get-caller-identity --profile john-doe` will work!

Likewise, the AWS SDK in most programs should work out of the box by setting an environment variable like `AWS_PROFILE=john-doe`.
