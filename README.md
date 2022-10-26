# Multiple keys per user
Describing a method which allows multiple ssh keys to be added to an AWS Transfer SFTP user via Terraform.

# Overview
For a while I struggled to add multiple `aws_transfer_ssh_key` resources to a single `aws_transfer_user` resource. I found a way and decided to put it on here for anyone else to find it. I over explained some Terraform concepts like `for` expressions and `for_each` meta-arguments - this was more for my own benefit but maybe it helps you too.

NOTE: This reads more like a guide/blog rather than a traditional README file.


## Structuring the data
Here is a simple way to define users for ous AWS Transfer SFTP server:
```json
[
    {
        "username": "ben",
        "ssh_public_keys": [
            "ssh-rsa AAAAB3NzaC1yc2EAAAADA1...",
            "ssh-rsa AAAAB3NzaC1yc2EAAAADA2..."
        ]
    },
    {
        "username": "bob",
        "ssh_public_keys": [
            "ssh-rsa AAAAB3NzaC1yc2EAAAADA3",
            "ssh-rsa AAAAB3NzaC1yc2EAAAADA4"
        ]
    }
]
```

It's worth noting a quick comment on [Resource Blocks](https://developer.hashicorp.com/terraform/language/resources/syntax):
> Each resource block describes one of more infrastructure objects

As the current (4.36.1) `aws` Terraform provider  only supports a single user-to-key reference for `aws_transfer_user` and `aws_transfer_ssh_key` resources, we have to flatten the data so it can be accessed by the [`for_each`](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each) meta-argument. _This is a slight over simplification and not strictly true, but if you're reading this you likely know exactly what I mean._

Let's define a local variable `raw_users` which mimics what we have in our JSON above:
```terraform
locals {
  raw_users = [
    {
      "username" : "ben",
      "ssh_public_keys" : [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADA1...",
        "ssh-rsa AAAAB3NzaC1yc2EAAAADA2...",
      ]
    },
    {
      "username" : "bob",
      "ssh_public_keys" : [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADA3...",
        "ssh-rsa AAAAB3NzaC1yc2EAAAADA4..."
      ]
    }
  ]
}
```

We can now inspect the data:
```bash
$ terraform console
> local.raw_users
[
  {
    "ssh_public_keys" = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADA1...",
      "ssh-rsa AAAAB3NzaC1yc2EAAAADA2...",
    ]
    "username" = "ben"
  },
	...
]
```

Let's create another local variable `flat_users` which will iterate over `local.raw_users` and return the data in a structure that can be used with `aws_transfer_user` and `aws_transfer_ssh_key` resources blocks:
```terraform
locals {
  raw_users = {
    ...
  }
  flat_users =  flatten([
    for users in local.raw_users : [
      for key in users.ssh_public_keys : {
         username       = users.username,
         ssh_public_key = key,
         index          = index(users.ssh_public_keys, key)
      }
    ]
  ])
}
```

This might seem a little complicated if you don't use [`for` Expressions](https://developer.hashicorp.com/terraform/language/expressions/for) often. Feel free to skip to [Creating the resources](#creating-the-resources), otherwise read on:

First, we iterate over each element of `var.raw_users`:
```terraform
for users in var.raw_users : [
    ...
]
```
where `users`, during the first iteration, would look like this:
```terraform
{
	"ssh_public_keys" = tolist([
		"ssh-rsa AAAAB3NzaC1yc2EAAAADAQ..."
		"ssh-rsa AAAAB3NzaC1yc2EAAAADAQ...",
	])
	"username" = "ben"
}
```
This allows us to get each `username` by calling `users.username`.

Next, we must iterate over each element of `ssh_public_keys`:
```
for key in users.ssh_public_keys : {
	...
}
```
which allows us to get each `ssh_public_key` by calling `key`.

Now we can build objects with all the necessary data for describing resources:
```
username       = users.username,
ssh_public_key = key,
index          = index(users.ssh_public_keys, key)
```

Bringing it all (almost) together:
```
flat_users = [
    for users in local.raw_users : [
      for key in users.ssh_public_keys : {
        username       = users.username,
        ssh_public_key = key,
        index          = index(users.ssh_public_keys, key)
      }
    ]
  ]
```

```bash
$ terraform console
> local.flat_users
[
  [
    {
      "index" = 0
      "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA1..."
      "username" = "ben"
    },
    {
      "index" = 1
      "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA2..."
      "username" = "ben"
    },
  ],
  [
    {
      "index" = 0
      "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA3..."
      "username" = "bob"
    },
    {
      "index" = 1
      "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA4..."
      "username" = "bob"
    },
  ],
]
```
_We use the [`index` function](https://developer.hashicorp.com/terraform/language/functions/index_function) so we can generate smaller resource names later on._


The above output is still far too nested to easily access the key value pairs so we use the terraform [flatten function](https://developer.hashicorp.com/terraform/language/functions/flatten) like so:
```
flat_users = flatten([
	...
])
```
we now get a list of objects with all the data we need!
```
[
  {
    "index" = 0
    "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA1..."
    "username" = "ben"
  },
  {
    "index" = 1
    "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA2..."
    "username" = "ben"
  },
  {
    "index" = 0
    "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA3..."
    "username" = "bob"
  },
  {
    "index" = 1
    "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA4..."
    "username" = "bob"
  },
]
```

## Creating the resources

Using the `for_each` meta-argument we can iterate over our `raw_user` and `flat_user` local variables to create our users and respective keys!

From the docs:
> If a resource or module block includes a for_each argument **whose value is a map or a set of strings**, Terraform creates one instance for each member of that map or set.

"But both `local.raw_users` and `local.flat_users` are of type `list(object)`!"

... Yes, sadly there's one last manipulation we have to do.


```terraform
resource "aws_transfer_user" "this" {
  for_each = { for user in local.raw_users : user.username => user }

  server_id      = aws_transfer_server.this.id
  user_name      = each.value.username
  role           = aws_iam_role.this.arn

```
Here we use [`Result Types`](https://developer.hashicorp.com/terraform/language/expressions/for#result-types) to produce an map.

```bash
$ terraform console
> { for user in local.raw_users : user.username => user }
{
  "ben" = {
    "ssh_public_keys" = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADA1...",
      "ssh-rsa AAAAB3NzaC1yc2EAAAADA2...",
    ]
    "username" = "ben"
  }
  "bob" = {
    "ssh_public_keys" = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADA3...",
      "ssh-rsa AAAAB3NzaC1yc2EAAAADA4...",
    ]
    "username" = "bob"
  }
}
```

and for the SSH keys:
```terraform
resource "aws_transfer_ssh_key" "this" {
  for_each = {
    for user in local.flat_users : "${user.username}-${user.index}" => user
  }

  server_id = aws_transfer_server.this.id
  user_name = each.value.username
  body      = each.value.ssh_public_key

  depends_on = [aws_transfer_user.this]
```

where
```bash
$ terraform console
> { for user in local.flat_users : "${user.username}-${user.index}" => user }
{
  "ben-0" = {
    "index" = 0
    "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA1..."
    "username" = "ben"
  }
  "ben-1" = {
    "index" = 1
    "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA2..."
    "username" = "ben"
  }
  "bob-0" = {
    "index" = 0
    "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA3..."
    "username" = "bob"
  }
  "bob-1" = {
    "index" = 1
    "ssh_public_key" = "ssh-rsa AAAAB3NzaC1yc2EAAAADA4..."
    "username" = "bob"
  }
}
```

If you run a Terraform plan you should see resources like these in the logs:
```
aws_transfer_user.this["ben"]: Refreshing state...
aws_transfer_user.this["bob"]: Refreshing state...
aws_transfer_ssh_key.this["ben-0"]: Refreshing state...
aws_transfer_ssh_key.this["ben-1"]: Refreshing state...
aws_transfer_ssh_key.this["bob-0"]: Refreshing state...
aws_transfer_ssh_key.this["bob-1"]: Refreshing state...
```
