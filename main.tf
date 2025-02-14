data "aws_instances" "instances_with_tag" {
  filter {
    name   = "tag:${var.filter_tag_key}"
    values = ["${var.filter_tag_value}"]
  }
  instance_state_names = ["running", "stopped"]
}

data "aws_instance" "filtered_instances" {
  for_each    = toset(data.aws_instances.instances_with_tag.ids)
  instance_id = each.key
}

locals {
  cutoff_date_local = timeadd(timestamp(), "${-(var.cutoff_days * 86400)}s")

  # Extract all volumes and match them with instance tags
  volume_map = flatten([
    for instance in data.aws_instance.filtered_instances : concat(
      [for root in instance.root_block_device : {
        id         = root.volume_id
        name       = lookup(root.tags, "Name", lookup(instance.tags, "Name", root.volume_id))
      }],
      [for ebs in instance.ebs_block_device : {
        id         = ebs.volume_id
        name       = lookup(ebs.tags, "Name", lookup(instance.tags, "Name", ebs.volume_id))
      }]
    )
  ])
}

resource "aws_ebs_snapshot" "snapshots" {
  for_each = { for vol in local.volume_map : vol.id => vol }

  volume_id   = each.value.id
  description = "Snapshot taken from arcus2 ${each.value.name}"

  tags = {
    "${var.filter_tag_key}" = var.filter_tag_value
    "Name"                  = "Snapshot-${each.value.name}"
  }

  timeouts {
    create = var.timeoutssettings
  }
}

resource "null_resource" "delete_old_snapshots" {
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOF
      #!/bin/bash
      if ! command -v pip3 &>/dev/null; then
          curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
          python3 get-pip.py
      fi
      python3 -m pip install --upgrade boto3
      python3 delete_snapshots.py ${local.cutoff_date_local} ${var.filter_tag_key} ${var.filter_tag_value} ${var.region}
    EOF
  }
}

output "instance_ids" {
  value = data.aws_instances.instances_with_tag.ids
}

output "volume_ids" {
  value = [for vol in local.volume_map : vol.id]
}

output "snapshot_ids" {
  value = [for snapshot in aws_ebs_snapshot.snapshots : snapshot.id]
}

output "cutoff_date" {
  value = local.cutoff_date_local
}
