{{- define "upright.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "upright.labels" -}}
app.kubernetes.io/name: {{ include "upright.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "upright.appHost" -}}
app.{{ .Values.hostname }}
{{- end }}

{{- define "upright.siteHost" -}}
{{ .Values.siteSubdomain }}.{{ .Values.hostname }}
{{- end }}

{{- define "upright.envSecret" -}}
{{ .Values.secretStore.targetSecretName }}
{{- end }}

{{- define "upright.secretStoreName" -}}
{{ .Values.secretStore.name }}
{{- end }}
