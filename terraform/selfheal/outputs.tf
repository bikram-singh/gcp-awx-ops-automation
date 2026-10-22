output "topic" {
  description = "Pub/Sub topic that receives the VM-stop events."
  value       = google_pubsub_topic.events.id
}

output "subscription" {
  description = "Subscription the bridge pulls from."
  value       = google_pubsub_subscription.bridge.id
}

output "bridge_secret" {
  description = "Kubernetes secret (in the AWX namespace) with the bridge's AWX credentials."
  value       = kubernetes_secret.bridge.metadata[0].name
}
