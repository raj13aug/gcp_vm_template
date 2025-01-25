locals {
  all_project_services = concat(var.gcp_service_list, [
    "storage.googleapis.com",
    "appengine.googleapis.com",
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
    max_replicas    = 4
    min_replicas    = 2
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}

resource "google_compute_instance_template" "foobar" {
  name         = "test-app-lb-group1-mig"
  machine_type = "e2-standard-4"
  tags         = ["allow-health-check"]

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    disk_size_gb = 250
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
}


resource "google_compute_target_pool" "foobar" {
  name = "my-target-pool"
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
}

locals {
  startup_script_path    = "startup-script.sh"
  startup_script_content = file(local.startup_script_path)
}


data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# health check
resource "google_compute_health_check" "default" {
  name     = "test-app-lb-hc"
  provider = google-beta
  project  = "project-id"
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

resource "google_compute_firewall" "default" {
  name          = "test-app-lb-fw-allow-hc"
  provider      = google-beta
  project       = "project-id"
  direction     = "INGRESS"
  network       = "default"
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
  }
  target_tags = ["allow-health-check"]
}

resource "google_compute_backend_service" "default" {
  name             = "test-app-lb-backend-default"
  provider         = google-beta
  project          = "project-id"
  protocol         = "HTTP"
  session_affinity = "GENERATED_COOKIE"
  # port_name               = "my-port"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  enable_cdn            = false
  health_checks         = [google_compute_health_check.default.id]
  backend {
    group           = google_compute_region_instance_group_manager.foobar.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}