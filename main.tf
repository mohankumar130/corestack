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
}

# Fetch all EBS Volumes
data "aws_ebs_volumes" "all_volumes" {}

# Create a map of volume IDs to their names
locals {
  volume_name_map = { 
    for vol in data.aws_ebs_volumes.all_volumes.ids : 
    vol => lookup(data.aws_ebs_volume.volume_details[vol].tags, "Name", vol) 
  }
}

data "aws_ebs_volume" "volume_details" {
  for_each  = toset(data.aws_ebs_volumes.all_volumes.ids)
  volume_id = each.key
}

resource "aws_ebs_snapshot" "snapshots" {
  for_each = toset(flatten([
    for instance in data.aws_instance.filtered_instances :
    concat(
      [for root in instance.root_block_device : root.volume_id],
      [for ebs in instance.ebs_block_device : ebs.volume_id]
    )
  ]))

  volume_id   = each.value
  description = "Snapshot of ${lookup(local.volume_name_map, each.value, each.value)}"

  tags = {
    "${var.filter_tag_key}" = var.filter_tag_value
    "Name"                  = "Snapshot-${lookup(local.volume_name_map, each.value, each.value)}"
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
  value = flatten([
    for inst in data.aws_instance.filtered_instances : 
    [for bd in inst.ebs_block_device : bd.volume_id]
  ])
}

output "snapshot_ids" {
  value = [for snapshot in aws_ebs_snapshot.snapshots : snapshot.id]
}

output "cutoff_date" {
  value = local.cutoff_date_local
}
