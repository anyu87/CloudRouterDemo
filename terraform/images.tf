# Get all Ubuntu images
# data "vkcs_images_images" "images" {
#   visibility = "public"
#   default    = true
#   properties = {
#     mcs_os_distro = "ubuntu"
#   }
# }

# List all Ubuntu images
# output "all_image_names" {
#   value = [for img in data.vkcs_images_images.images.images : img.name]
# }