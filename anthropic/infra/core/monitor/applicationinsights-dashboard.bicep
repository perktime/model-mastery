param name string
param location string
param tags object
param applicationInsightsId string

var portalBase = 'https://portal.azure.com/#resource${applicationInsightsId}'

resource dashboard 'Microsoft.Portal/dashboards@2020-09-01-preview' = {
  name: name
  location: location
  tags: union(tags, {
    'hidden-title': name
  })
  properties: {
    lenses: [
      {
        order: 0
        parts: [
          {
            position: {
              x: 0
              y: 0
              colSpan: 6
              rowSpan: 5
            }
            metadata: {
              type: 'Extension/HubsExtension/PartType/MarkdownPart'
              settings: {
                content: {
                  settings: {
                    title: 'Sparkles observability'
                    subtitle: 'Local agent and loop telemetry'
                    content: '''
                      ## Application Insights
                      Open the linked resource, then select the corresponding monitoring blade:
                      '''
                  }
                }
              }
              inputs: []
            }
          }
          {
            position: {
              x: 6
              y: 0
              colSpan: 6
              rowSpan: 5
            }
            metadata: {
              type: 'Extension/HubsExtension/PartType/MarkdownPart'
              settings: {
                content: {
                  settings: {
                    title: 'Monitoring views'
                    content: '[Overview](${portalBase}/overview)\n\n[Live metrics](${portalBase}/quickPulse)\n\n[Availability](${portalBase}/availability)\n\n[Application map](${portalBase}/applicationMap)\n\n[Usage](${portalBase}/users)\n\n[Failures](${portalBase}/failures)\n\n[Performance](${portalBase}/performance)\n\nAvailability requires separately configured tests.'
                  }
                }
              }
              inputs: []
            }
          }
        ]
      }
    ]
    metadata: {
      model: {
        timeRange: {
          value: {
            relative: {
              duration: 24
              timeUnit: 1
            }
          }
          type: 'MsPortalFx.Composition.Configuration.ValueTypes.TimeRange'
        }
      }
    }
  }
}

output id string = dashboard.id
