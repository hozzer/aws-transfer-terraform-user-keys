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

  flat_users = flatten([
    for users in local.raw_users : [
      for key in users.ssh_public_keys : {
        username       = users.username,
        ssh_public_key = key,
        index          = index(users.ssh_public_keys, key)
      }
    ]
  ])

}
resource "aws_transfer_user" "this" {
  for_each = { for user in local.raw_users : user.username => user }

  server_id = aws_transfer_server.this.id
  user_name = each.value.username
  role      = aws_iam_role.this.arn
}

resource "aws_transfer_ssh_key" "this" {
  for_each = { for user in local.flat_users : "${user.username}-${user.index}" => user }

  server_id = aws_transfer_server.this.id
  user_name = each.value.username
  body      = each.value.ssh_public_key

  depends_on = [aws_transfer_user.this]
}
