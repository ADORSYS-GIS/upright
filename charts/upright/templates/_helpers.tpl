{{- define "upright.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "upright.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
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
upright-secret
{{- end }}

{{- define "upright.appEnv" -}}
- name: UPRIGHT_HOSTNAME
  value: {{ .Values.hostname | quote }}
- name: SITE_SUBDOMAIN
  value: {{ .Values.siteSubdomain | quote }}
- name: PROMETHEUS_URL
  value: http://{{ include "upright.fullname" . }}-prometheus:9090
- name: ALERTMANAGER_URL
  value: http://{{ include "upright.fullname" . }}-alertmanager:9093
{{- end }}

