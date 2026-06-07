#!/bin/bash
# Ce script installe le Metrics Server sur le cluster Kubernetes.
# Il est nécessaire pour que le HorizontalPodAutoscaler puisse collecter
# les métriques CPU des pods et scaler automatiquement.
#
# A exécuter une seule fois lors de la configuration initiale du cluster.
# Compatible avec DigitalOcean Kubernetes (DOKS).

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
