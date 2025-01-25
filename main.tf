locals {
  all_project_services = concat(var.gcp_service_list, [
    "storage.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbuild.googleapis.com",

  ])
}

resource "google_project_service" "enabled_apis" {
  project                    = var.project_id
  for_each                   = toset(local.all_project_services)
  service                    = each.key
  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "time_sleep" "wait_project_init" {
  create_duration = "90s"

  depends_on = [google_project_service.enabled_apis]
}

resource "google_compute_region_autoscaler" "foobar" {
  name   = "my-region-autoscaler"
  region = "us-central1"
  target = google_compute_region_instance_group_manager.foobar.id

  autoscaling_policy {
    max_replicas    = 1
    min_replicas    = 1
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
  depends_on = [time_sleep.wait_project_init]
}

resource "google_compute_instance_template" "foobar" {
  name         = "test-app-lb-group1-mig"
  machine_type = "e2-micro"
  tags         = ["allow-health-check"]

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_size_gb = 30
  }

  network_interface {
    network = "default"

    # secret default
    access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    startup-script = local.startup_script_content
  }
  depends_on = [time_sleep.wait_project_init]
}


resource "google_compute_target_pool" "foobar" {
  name       = "my-target-pool"
  depends_on = [time_sleep.wait_project_init]
}


resource "google_compute_region_instance_group_manager" "foobar" {
  name   = "test-app-lb-group1-mig"
  region = "us-central1"

  version {
    instance_template = google_compute_instance_template.foobar.id
    name              = "primary"
  }

  target_pools       = [google_compute_target_pool.foobar.id]
  base_instance_name = "foobar"
  depends_on         = [time_sleep.wait_project_init]
}

locals {
  startup_script_path    = "startup-script.sh"
  startup_script_content = file(local.startup_script_path)
}


data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

resource "google_compute_global_address" "default" {
  provider   = google-beta
  project    = var.project_id
  name       = "test-static-ip"
  depends_on = [time_sleep.wait_project_init]
}

# forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "test-app-lb"
  provider              = google-beta
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "HTTP"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
  depends_on            = [time_sleep.wait_project_init]
}

# http proxy
resource "google_compute_target_http_proxy" "default" {
  name       = "test-app-lb-http-proxy"
  provider   = google-beta
  project    = var.project_id
  url_map    = google_compute_url_map.default.id
  depends_on = [time_sleep.wait_project_init]
}

# url map
resource "google_compute_url_map" "default" {
  name            = "test-app-lb-map"
  provider        = google-beta
  project         = var.project_id
  default_service = google_compute_backend_service.default.id
  depends_on      = [time_sleep.wait_project_init]
}



# health check
resource "google_compute_health_check" "default" {
  name     = "test-app-lb-hc"
  provider = google-beta
  project  = var.project_id
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
  depends_on = [time_sleep.wait_project_init]
}

resource "google_compute_firewall" "default" {
  name          = "test-app-lb-fw-allow-hc"
  provider      = google-beta
  project       = var.project_id
  direction     = "INGRESS"
  network       = "default"
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
  }
  target_tags = ["allow-health-check"]
  depends_on  = [time_sleep.wait_project_init]
}

resource "google_compute_backend_service" "default" {
  name                  = "test-app-lb-backend-default"
  provider              = google-beta
  project               = var.project_id
  protocol              = "HTTP"
  session_affinity      = "GENERATED_COOKIE"
  port_name             = "80"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  enable_cdn            = false
  health_checks         = [google_compute_health_check.default.id]
  backend {
    group           = google_compute_region_instance_group_manager.foobar.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  depends_on = [time_sleep.wait_project_init]
}