variable "yourname" {
  description = "sandy"
  type        = string
}
 
variable "location" {
  description = "Azure region to deploy into."
  type        = string
  default     = "East US"
}
 
variable "alert_email" {
  description = "sm4rc3cd@gmail.com"
  type        = string
}
 
variable "tags" {
  type = map(string)
  default = {
    project     = "cost-dashboard"
    environment = "dev"
    managed_by  = "terraform"
  }
}
