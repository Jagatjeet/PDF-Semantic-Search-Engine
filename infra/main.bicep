// Azure Bicep – deploy PDF Search app to Azure Container Apps
// Usage:
//   az group create -n pdf-search-rg -l eastus
//   az deployment group create -g pdf-search-rg -f main.bicep -p acrName=<your-acr>

@description('Azure Container Registry name (must already exist and images pushed)')
param acrName string

@description('Location')
param location string = resourceGroup().location

var acrLoginServer = '${acrName}.azurecr.io'

// ── User-assigned managed identity for ACR pull ───────────────────────────────
resource acrPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'pdf-search-acr-pull'
  location: location
}

// Reference the existing ACR so we can scope the role assignment to it
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// Grant AcrPull to the managed identity on the ACR
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acrPullIdentity.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: acrPullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Log Analytics workspace ──────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'pdf-search-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Container Apps Environment ───────────────────────────────────────────────
resource caEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'pdf-search-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      // Default consumption profile for all other apps
      { name: 'Consumption', workloadProfileType: 'Consumption' }
      // Dedicated D4 profile for Ollama (4 vCPU, 16 GiB)
      { name: 'ollama-d4', workloadProfileType: 'D4', minimumCount: 1, maximumCount: 1 }
    ]
  }
}

// ── Qdrant ───────────────────────────────────────────────────────────────────
resource qdrant 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'qdrant'
  location: location
  properties: {
    managedEnvironmentId: caEnv.id
    configuration: {
      ingress: {
        external: false
        targetPort: 6333
        transport: 'http'
      }
    }
    template: {
      containers: [
        {
          name: 'qdrant'
          image: 'qdrant/qdrant:v1.9.2'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          volumeMounts: [
            { volumeName: 'qdrant-storage', mountPath: '/qdrant/storage' }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 1 }
      volumes: [
        { name: 'qdrant-storage', storageType: 'EmptyDir' }
      ]
    }
  }
}

// ── Ollama (Mistral) ─────────────────────────────────────────────────────────
resource ollama 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ollama'
  location: location
  properties: {
    managedEnvironmentId: caEnv.id
    // Run on the dedicated D4 profile (4 vCPU / 16 GiB) — Mistral needs ~4.5 GiB
    workloadProfileName: 'ollama-d4'
    configuration: {
      ingress: {
        external: true
        targetPort: 11434
        transport: 'http'
      }
    }
    template: {
      containers: [
        {
          name: 'ollama'
          image: 'ollama/ollama:latest'
          command: ['/bin/sh', '-c', 'ollama serve & sleep 10 && ollama pull mistral; wait']
          resources: { cpu: json('4'), memory: '14Gi' }
          volumeMounts: [
            { volumeName: 'ollama-data', mountPath: '/root/.ollama' }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 1 }
      volumes: [
        { name: 'ollama-data', storageType: 'EmptyDir' }
      ]
    }
  }
}

// ── Backend ──────────────────────────────────────────────────────────────────
resource backend 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'pdf-search-backend'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  dependsOn: [acrPullRoleAssignment]
  properties: {
    managedEnvironmentId: caEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'http'
      }
      registries: [
        { server: acrLoginServer, identity: acrPullIdentity.id }
      ]
    }
    template: {
      containers: [
        {
          name: 'backend'
          image: '${acrLoginServer}/pdf-search-backend:latest'
          // PyTorch + nomic-embed-text-v1.5 weights require ~2-2.5 GB RAM; 4Gi gives safe headroom
          resources: { cpu: json('2'), memory: '4Gi' }
          env: [
            { name: 'QDRANT_HOST', value: 'qdrant' }
            // ACA internal ingress always routes on port 80, regardless of the container's targetPort
            { name: 'QDRANT_PORT', value: '80' }
            { name: 'QDRANT_COLLECTION', value: 'pdf_docs' }
            { name: 'OLLAMA_HOST', value: 'http://ollama' }
            { name: 'OLLAMA_MODEL', value: 'mistral' }
            // Model weights are baked into the image; block outbound HuggingFace calls at runtime
            { name: 'TRANSFORMERS_OFFLINE', value: '1' }
            { name: 'HF_DATASETS_OFFLINE', value: '1' }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

// ── Frontend ─────────────────────────────────────────────────────────────────
resource frontend 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'pdf-search-frontend'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  dependsOn: [acrPullRoleAssignment]
  properties: {
    managedEnvironmentId: caEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        transport: 'http'
      }
      registries: [
        { server: acrLoginServer, identity: acrPullIdentity.id }
      ]
    }
    template: {
      containers: [
        {
          name: 'frontend'
          image: '${acrLoginServer}/pdf-search-frontend:latest'
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          env: [
            // Use the backend's full FQDN so ACA ingress routes correctly via Host header
            { name: 'BACKEND_URL', value: 'https://${backend.properties.configuration.ingress.fqdn}' }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output frontendUrl string = 'https://${frontend.properties.configuration.ingress.fqdn}'
output backendUrl string = 'https://${backend.properties.configuration.ingress.fqdn}'
output ollamaUrl string = 'https://${ollama.properties.configuration.ingress.fqdn}'
