"""
Per-model max concurrency for the LiteLLM proxy.

Rejects requests with HTTP 429 when a model already has `max_parallel_requests`
requests in flight, instead of silently queueing them (the built-in router
semaphore behavior).

The limit is read from the model's existing `litellm_params.max_parallel_requests`
in config.yaml, so configuration stays in one place. If a model_name has several
deployments, their limits are summed.

Counts cover the full request lifetime, including streaming (the success/failure
callbacks fire when the stream finishes, not when it starts), which the built-in
router semaphore does not handle.

Usage — put this file next to your proxy config.yaml, then:

  litellm_settings:
    callbacks: model_concurrency_limiter.limiter_instance
"""

import time
from typing import Optional

from fastapi import HTTPException

from litellm.integrations.custom_logger import CustomLogger

# In-flight entries older than this are assumed leaked (e.g. client disconnected
# and no failure callback fired) and are pruned so the limiter self-heals.
STALE_AFTER_SECONDS = 600


class ModelConcurrencyLimiter(CustomLogger):
    def __init__(self):
        # model_name -> {litellm_call_id: started_at}
        self._inflight: dict = {}

    def _limit_for(self, model: Optional[str]) -> Optional[int]:
        if not model:
            return None
        from litellm.proxy import proxy_server

        router = getattr(proxy_server, "llm_router", None)
        if router is None:
            return None
        deployments = router.get_model_list(model_name=model) or []
        limits = [
            d.get("litellm_params", {}).get("max_parallel_requests")
            for d in deployments
        ]
        limits = [lim for lim in limits if isinstance(lim, int)]
        if not limits:
            return None
        return sum(limits)

    def _prune(self, reqs: dict) -> None:
        cutoff = time.time() - STALE_AFTER_SECONDS
        for call_id, started_at in list(reqs.items()):
            if started_at < cutoff:
                reqs.pop(call_id, None)

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        model = data.get("model")
        limit = self._limit_for(model)
        if limit is None:
            return data

        reqs = self._inflight.setdefault(model, {})
        self._prune(reqs)
        if len(reqs) >= limit:
            raise HTTPException(
                status_code=429,
                detail={
                    "error": (
                        f"Model '{model}' is busy: {len(reqs)}/{limit} requests "
                        "in flight. Please retry later."
                    )
                },
                headers={"Retry-After": "10"},
            )

        call_id = data.get("litellm_call_id")
        if call_id:
            reqs[call_id] = time.time()
        return data

    def _release(self, kwargs) -> None:
        call_id = kwargs.get("litellm_call_id") or (
            kwargs.get("litellm_params") or {}
        ).get("litellm_call_id")
        if call_id is None:
            return
        for reqs in self._inflight.values():
            if reqs.pop(call_id, None) is not None:
                return

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._release(kwargs)

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        self._release(kwargs)


limiter_instance = ModelConcurrencyLimiter()
