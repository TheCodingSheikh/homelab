import os
from typing import List, Optional

from fastapi_sso.sso.base import OpenID

import litellm
from litellm._logging import verbose_proxy_logger
from litellm.proxy._types import LitellmUserRoles, SSOUserDefinedValues
from litellm.proxy.proxy_server import prisma_client


async def custom_sso_handler(userIDPInfo: OpenID) -> SSOUserDefinedValues:
    """
    Custom SSO handler that:
    1. Gets role from userIDPInfo.user_role (already extracted by LiteLLM using GENERIC_USER_ROLE_ATTRIBUTE)
    2. Gets models from default_internal_user_params (supports wildcards)
    3. Updates existing users in DB on every login
    """
    if userIDPInfo.id is None:
        raise ValueError("No ID found for user")

    # Role is already extracted by LiteLLM's generic_response_convertor()
    # using GENERIC_USER_ROLE_ATTRIBUTE env var
    user_role = getattr(userIDPInfo, "user_role", None)

    # Convert enum to string if needed
    if user_role and isinstance(user_role, LitellmUserRoles):
        user_role = user_role.value

    # Fallback to default
    if not user_role:
        if litellm.default_internal_user_params:
            user_role = litellm.default_internal_user_params.get("user_role")
        if not user_role:
            user_role = LitellmUserRoles.INTERNAL_USER.value

    # Get models from config (supports wildcards like "openai/*")
    models: List[str] = []
    max_budget: Optional[float] = None
    budget_duration: Optional[str] = None

    if litellm.default_internal_user_params:
        models = litellm.default_internal_user_params.get("models", [])
        max_budget = litellm.default_internal_user_params.get("max_budget")
        budget_duration = litellm.default_internal_user_params.get("budget_duration")

    # Update existing user in DB (makes models/role dynamic on every login)
    if prisma_client:
        try:
            await prisma_client.db.litellm_usertable.update_many(
                where={"user_id": userIDPInfo.id},
                data={"models": models, "user_role": user_role},
            )
            verbose_proxy_logger.info(f"Updated user {userIDPInfo.id}: models={models}, role={user_role}")
        except Exception as e:
            verbose_proxy_logger.error(f"Error updating user: {e}")

    return SSOUserDefinedValues(
        models=models,
        user_id=userIDPInfo.id,
        user_email=userIDPInfo.email,
        user_role=user_role,
        max_budget=max_budget,
        budget_duration=budget_duration,
    )
