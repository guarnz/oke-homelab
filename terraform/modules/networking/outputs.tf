output "vcn_id" {
  value = module.vcn.vcn_id
}

output "public_subnet_id" {
  value = oci_core_subnet.public.id
}

output "private_subnet_1_id" {
  value = oci_core_subnet.private_1.id
}

output "private_subnet_2_id" {
  value = oci_core_subnet.private_2.id
}
