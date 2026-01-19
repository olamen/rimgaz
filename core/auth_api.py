from django.contrib.auth.models import Group

from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.views import TokenObtainPairView


def _compute_role(user) -> str:
	"""Détermine le rôle applicatif de l'utilisateur pour le mobile/backoffice."""

	# Admin / staff
	if user.is_superuser or user.is_staff:
		return "admin"

	# Rôle chauffeur basé sur le profil lié
	if hasattr(user, "driver_profile") and user.driver_profile is not None:
		return "driver"

	# Rôle client basé sur le profil lié
	if hasattr(user, "client_profile") and user.client_profile is not None:
		return "client"

	# Fallback sur les groupes si configurés
	group_names = {name.lower() for name in user.groups.values_list("name", flat=True)}

	if any(name in group_names for name in {"driver", "drivers", "chauffeur", "chauffeurs"}):
		return "driver"
	if any(name in group_names for name in {"client", "clients"}):
		return "client"

	return "user"


class RimgazTokenObtainPairSerializer(TokenObtainPairSerializer):
	@classmethod
	def get_token(cls, user):
		token = super().get_token(user)
		token["role"] = _compute_role(user)
		return token

	def validate(self, attrs):
		data = super().validate(attrs)
		role = _compute_role(self.user)
		data["role"] = role
		data["username"] = self.user.get_username()
		return data


class RimgazTokenObtainPairView(TokenObtainPairView):
	serializer_class = RimgazTokenObtainPairSerializer

