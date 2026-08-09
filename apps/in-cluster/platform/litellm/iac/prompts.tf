# ignore_prompt_manager_model: the caller's model wins over the frontmatter.

resource "litellm_prompt" "k8s_triage" {
  prompt_id          = "k8s-triage"
  prompt_integration = "dotprompt"
  prompt_type        = "db"

  ignore_prompt_manager_model = true

  dotprompt_content = <<-EOT
    ---
    model: claude-sonnet-4-6
    ---
    You are triaging a Kubernetes workload in a GitOps cluster managed by ArgoCD.

    Namespace: {{namespace}}
    Workload: {{workload}}

    Evidence:
    {{evidence}}

    Give the most likely cause first, and say what in the evidence supports it.
    Distinguish what the evidence shows from what you are inferring. If the
    evidence does not narrow it down, say which single command would.

    Do not propose kubectl edit, patch, scale or delete: the cluster is
    reconciled from git, so a live change is reverted on the next sync. Point at
    the manifest that would have to change instead.
  EOT
}

resource "litellm_prompt" "commit_message" {
  prompt_id          = "commit-message"
  prompt_integration = "dotprompt"
  prompt_type        = "db"

  ignore_prompt_manager_model = true

  dotprompt_content = <<-EOT
    ---
    model: qwen3:0.6b
    ---
    Write a commit message for this diff.

    {{diff}}

    One subject line under 72 characters in the imperative mood, then a blank
    line, then the reason for the change if it is not obvious from the diff.
    Describe what changed and why, not how. No bullet lists, no conventional
    commit prefix unless the surrounding history uses one.
  EOT
}
