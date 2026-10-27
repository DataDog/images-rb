# ECR Public authentication

Runtime and service image builds authenticate to `public.ecr.aws` using
short-lived AWS credentials obtained through GitHub OIDC. This avoids the
[anonymous pull limits](https://docs.aws.amazon.com/AmazonECR/latest/public/public-service-quotas.html).
Compiler variants consume the runtime images published to GHCR by the same
workflow run.

## AWS role

Create an IAM OIDC provider for `https://token.actions.githubusercontent.com`
with audience `sts.amazonaws.com`, unless the account already has one.

Create a dedicated role with this trust policy, replacing `<AWS_ACCOUNT_ID>`
with the account hosting the role. The subject matches the repository's
default OIDC format for branch pushes and manually dispatched branch runs.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:DataDog/images-rb:ref:refs/heads/*"
        }
      }
    }
  ]
}
```

Attach this permission policy. Both authentication actions require
`Resource: "*"`; the role does not need image-publishing permissions.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr-public:GetAuthorizationToken",
        "sts:GetServiceBearerToken"
      ],
      "Resource": "*"
    }
  ]
}
```

## Repository configuration

Set the repository Actions variable `AWS_ECR_PUBLIC_ROLE_ARN` to the role's
ARN. No long-lived AWS access keys are required. The Main workflow checks
that this variable is set before starting the image matrices.

The reusable workflows pass `id-token: write` through every caller to the
build jobs. AWS credentials are configured with
`aws-actions/configure-aws-credentials`, then the AWS CLI supplies a registry
password directly to `docker login --password-stdin`. ECR Public
[authentication uses `us-east-1`](https://docs.aws.amazon.com/AmazonECR/latest/public/public-registry-auth.html)
and its registry token is valid for 12 hours.

After configuring the role and variable, validate a branch build on both
x86_64 and aarch64 before merging changes to this authentication setup.
Missing configuration or an authentication error fails the image build
rather than silently falling back to anonymous pulls.
