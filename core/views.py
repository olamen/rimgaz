from django.contrib.admin.views.decorators import staff_member_required
from django.contrib.auth import logout, get_user_model
from django.contrib.auth.decorators import login_required
from django.shortcuts import render, redirect

from rest_framework import viewsets, mixins, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response

from .models import (
	Client,
	Bus,
	Tour,
	BusPosition,
	Wallet,
	Payment,
	GasBottleType,
	ClientBottleBalance,
	Driver,
	Warehouse,
	WarehouseBottleStock,
	BusBottleStock,
	GeofenceZone,
	BusAlert,
	ActivityLog,
	PaymentStatusHistory,
	ClientOrder,
)
from .serializers import (
	ClientSerializer,
	BusSerializer,
	DriverSerializer,
	TourSerializer,
	BusPositionSerializer,
	WalletSerializer,
	PaymentSerializer,
	PaymentStatusHistorySerializer,
	GasBottleTypeSerializer,
	ClientBottleBalanceSerializer,
	WarehouseSerializer,
	WarehouseBottleStockSerializer,
	BusBottleStockSerializer,
	GeofenceZoneSerializer,
	BusAlertSerializer,
	ActivityLogSerializer,
	ClientSelfPaymentSerializer,
	ClientOrderSerializer,
	UserSerializer,
)


User = get_user_model()


def logout_view(request):
	"""Déconnecte l'utilisateur puis le redirige vers la page de login."""
	logout(request)
	return redirect("login")


class AuditedModelViewSet(viewsets.ModelViewSet):
	"""ModelViewSet de base qui crée une trace dans ActivityLog pour chaque action CRUD."""

	def _snapshot_instance(self, instance):
		"""Retourne un dict simple des champs de base de l'instance (sans M2M)."""
		if instance is None:
			return {}
		data = {}
		for field in instance._meta.fields:
			name = field.name
			try:
				value = getattr(instance, name)
			except Exception:
				continue
			# Pour les FK, stocker la valeur brute (pk) plutôt que l'objet complet
			if hasattr(value, "pk") and not isinstance(value, (str, int, float, bool)):
				data[name] = getattr(value, "pk", None)
			else:
				data[name] = value
		return data

	def _build_changes(self, before: dict, after: dict) -> dict:
		"""Construit un dict des champs modifiés: {field: {old, new}}."""
		changes = {}
		# Ignorer les champs purement techniques
		ignored = {"id", "pk", "created_at", "updated_at"}
		for field, old in before.items():
			if field in ignored:
				continue
			new = after.get(field)
			if old != new:
				changes[field] = {"old": old, "new": new}
		return changes

	def _log(self, instance, action: str, description: str = "", extra_data: dict | None = None):
		# Génération automatique d'une description lisible si non fournie
		try:
			if not description:
				model_verbose = getattr(instance._meta, "verbose_name", instance.__class__.__name__)
				obj_id = getattr(instance, "pk", None)
				base = f"{model_verbose}"
				if obj_id is not None:
					base = f"{base} #{obj_id}"
				if action == ActivityLog.ACTION_CREATE:
					description = f"Création de {base}"
				elif action == ActivityLog.ACTION_UPDATE:
					description = f"Mise à jour de {base}"
				elif action == ActivityLog.ACTION_DELETE:
					description = f"Suppression de {base}"
				else:
					description = f"Action {action} sur {base}"
		except Exception:
			# Si la génération automatique échoue, on garde la description brute
			pass

		try:
			ActivityLog.objects.create(
				user=getattr(self.request, "user", None) if hasattr(self, "request") else None,
				model_name=instance._meta.label,
				object_id=str(getattr(instance, "pk", "")),
				action=action,
				description=description,
				data=extra_data or None,
			)
		except Exception:
			# Ne jamais casser l'API à cause de la journalisation
			pass

	def perform_create(self, serializer):
		instance = serializer.save()
		self._log(instance, ActivityLog.ACTION_CREATE)
		return instance

	def perform_update(self, serializer):
		before = self._snapshot_instance(serializer.instance)
		instance = serializer.save()
		after = self._snapshot_instance(instance)
		changes = self._build_changes(before, after)
		desc = ""
		if changes:
			parts = []
			for field, vals in changes.items():
				parts.append(f"{field}: '{vals['old']}' -> '{vals['new']}'")
			fields_str = "; ".join(parts)
			desc = f"Champs modifiés: {fields_str}"
		self._log(instance, ActivityLog.ACTION_UPDATE, description=desc, extra_data={"changes": changes} if changes else None)
		return instance

	def perform_destroy(self, instance):
		self._log(instance, ActivityLog.ACTION_DELETE)
		return super().perform_destroy(instance)


class ClientViewSet(AuditedModelViewSet):
	queryset = Client.objects.all().order_by("id")
	serializer_class = ClientSerializer


class UserViewSet(AuditedModelViewSet):
	serializer_class = UserSerializer

	def get_queryset(self):
		user = getattr(self.request, "user", None)
		if not user or not (user.is_authenticated and (user.is_staff or user.is_superuser)):
			raise PermissionDenied("Seul un administrateur peut gérer les utilisateurs.")
		return User.objects.all().order_by("username")


class BusViewSet(AuditedModelViewSet):
	queryset = Bus.objects.all().order_by("id")
	serializer_class = BusSerializer


class DriverViewSet(AuditedModelViewSet):
	queryset = Driver.objects.select_related("bus").all().order_by("id")
	serializer_class = DriverSerializer


class TourViewSet(AuditedModelViewSet):
	queryset = Tour.objects.select_related("bus", "driver").all().order_by("-date")
	serializer_class = TourSerializer


class BusPositionViewSet(mixins.CreateModelMixin, mixins.ListModelMixin, viewsets.GenericViewSet):
	"""Permet de créer de nouvelles positions (côté chauffeur) et de lister les positions (côté back-office)."""

	queryset = BusPosition.objects.select_related("bus", "tour").all().order_by("-created_at")
	serializer_class = BusPositionSerializer

	def perform_create(self, serializer):
		position = serializer.save()

		# Speed limit alert
		bus = position.bus
		if position.speed_kmh is not None and bus.max_speed_kmh is not None:
			try:
				if float(position.speed_kmh) > float(bus.max_speed_kmh):
					BusAlert.objects.create(
						bus=bus,
						position=position,
						alert_type=BusAlert.TYPE_SPEED,
						message=f"Vitesse {position.speed_kmh} km/h > limite {bus.max_speed_kmh} km/h",
					)
			except (TypeError, ValueError):
				pass

		# Geofencing alert (outside all active zones)
		zones = GeofenceZone.objects.filter(is_active=True)
		if zones.exists():
			from math import radians, sin, cos, asin, sqrt

			def haversine(lat1, lon1, lat2, lon2):
				# distance in meters
				R = 6371000.0
				phi1, phi2 = radians(lat1), radians(lat2)
				dphi = radians(lat2 - lat1)
				dlambda = radians(lon2 - lon1)
				a = sin(dphi / 2) ** 2 + cos(phi1) * cos(phi2) * sin(dlambda / 2) ** 2
				c = 2 * asin(sqrt(a))
				return R * c

			try:
				lat = float(position.latitude)
				lon = float(position.longitude)
			except (TypeError, ValueError):
				return

			def point_in_polygon(point_lat, point_lon, polygon):
				# polygon: list of [lat, lon]
				n = len(polygon)
				inside = False
				if n < 3:
					return False
				for i in range(n):
					lat1, lon1 = polygon[i]
					lat2, lon2 = polygon[(i + 1) % n]
					# Ray casting algorithm on longitude axis
					if ((lon1 > point_lon) != (lon2 > point_lon)):
						intersect_lat = (lat2 - lat1) * (point_lon - lon1) / (lon2 - lon1 + 1e-12) + lat1
						if point_lat < intersect_lat:
							inside = not inside
				return inside

			inside_any = False
			for z in zones:
				# If polygon is defined, use it
				if z.polygon:
					try:
						poly = [
							(float(pt[0]), float(pt[1]))
							for pt in z.polygon
						]
					except (TypeError, ValueError, IndexError):
						poly = []
					if poly and point_in_polygon(lat, lon, poly):
						inside_any = True
						break
				# Fallback to circle if center/radius are set
				elif z.center_latitude is not None and z.center_longitude is not None and z.radius_meters is not None:
					try:
						cz_lat = float(z.center_latitude)
						cz_lon = float(z.center_longitude)
						if haversine(lat, lon, cz_lat, cz_lon) <= z.radius_meters:
							inside_any = True
							break
					except (TypeError, ValueError):
						continue

			if not inside_any:
				BusAlert.objects.create(
					bus=bus,
					position=position,
					alert_type=BusAlert.TYPE_GEOFENCE,
					message="Bus hors des zones autorisées",
				)


class WalletViewSet(viewsets.ReadOnlyModelViewSet):
	queryset = Wallet.objects.select_related("client").all().order_by("client__name")
	serializer_class = WalletSerializer



class PaymentViewSet(AuditedModelViewSet):
	queryset = Payment.objects.select_related("client").all().order_by("-created_at")
	serializer_class = PaymentSerializer

	def perform_create(self, serializer):
		# Toute demande de paiement créée via l'API est en attente
		instance = serializer.save(status=Payment.PENDING)
		PaymentStatusHistory.objects.create(
			payment=instance,
			previous_status=None,
			new_status=Payment.PENDING,
			changed_by=getattr(self.request, "user", None),
			note="Création de la demande de paiement",
		)
		self._log(instance, ActivityLog.ACTION_CREATE, "Création de paiement en attente")
		return instance

	def perform_update(self, serializer):
		payment = self.get_object()
		old_status = payment.status
		before = self._snapshot_instance(payment)
		instance = serializer.save()
		new_status = instance.status
		after = self._snapshot_instance(instance)
		changes = self._build_changes(before, after)
		changes_data = {"changes": changes} if changes else None

		if old_status != new_status and new_status in (Payment.VALIDATED, Payment.REJECTED):
			user = getattr(self.request, "user", None)
			if not (user and (user.is_superuser or user.has_perm("core.can_validate_payments"))):
				raise PermissionDenied("Seul un utilisateur financier peut valider ou rejeter un paiement.")
			PaymentStatusHistory.objects.create(
				payment=instance,
				previous_status=old_status,
				new_status=new_status,
				changed_by=user,
				note="Changement de statut via le back-office",
			)
			desc = f"Changement de statut {old_status} -> {new_status}"
			if changes:
				parts = []
				for field, vals in changes.items():
					parts.append(f"{field}: '{vals['old']}' -> '{vals['new']}'")
				fields_str = "; ".join(parts)
				desc = f"{desc} | Champs modifiés: {fields_str}"
			self._log(
				instance,
				ActivityLog.ACTION_UPDATE,
				desc,
				extra_data=changes_data,
			)
		else:
			# Mise à jour classique sans changement de statut critique
			desc = ""
			if changes:
				parts = []
				for field, vals in changes.items():
					parts.append(f"{field}: '{vals['old']}' -> '{vals['new']}'")
				fields_str = "; ".join(parts)
				desc = f"Champs modifiés: {fields_str}"
			self._log(instance, ActivityLog.ACTION_UPDATE, description=desc, extra_data=changes_data)
		return instance


class ClientOrderViewSet(mixins.CreateModelMixin, mixins.ListModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
	serializer_class = ClientOrderSerializer

	def get_client(self):
		user = getattr(self.request, "user", None)
		if not user or not user.is_authenticated:
			raise PermissionDenied("Seuls les comptes clients peuvent créer des commandes.")
		from .models import Client  # import local to avoid circular issues
		try:
			return user.client_profile
		except Client.DoesNotExist:
			raise PermissionDenied("Seuls les comptes clients peuvent créer des commandes.")

	def get_queryset(self):
		user = getattr(self.request, "user", None)
		# Back-office users: staff, superadmins ou financiers peuvent voir toutes les commandes
		if user and user.is_authenticated and (user.is_staff or user.is_superuser or user.has_perm("core.can_validate_payments")):
			return ClientOrder.objects.select_related("client", "bottle_type").order_by("-created_at")
		client = self.get_client()
		return ClientOrder.objects.filter(client=client).select_related("bottle_type").order_by("-created_at")

	def perform_update(self, serializer):
		user = getattr(self.request, "user", None)
		if not user or not user.is_authenticated:
			raise PermissionDenied("Authentification requise.")
		# Seuls les utilisateurs financiers ou superadmins peuvent modifier le statut
		if not (user.is_superuser or user.has_perm("core.can_validate_payments")):
			raise PermissionDenied("Seul un utilisateur financier peut modifier une commande.")

		before_status = serializer.instance.status
		instance = serializer.save()
		after_status = instance.status
		ActivityLog.objects.create(
			user=user,
			model_name=ClientOrder._meta.label,
			object_id=str(instance.pk),
			action=ActivityLog.ACTION_UPDATE,
			description=f"Changement de statut commande {before_status} -> {after_status}",
			data={
				"before_status": before_status,
				"after_status": after_status,
			},
		)
		return instance

	def perform_create(self, serializer):
		client = self.get_client()
		bottle_type = serializer.validated_data["bottle_type"]
		quantity = serializer.validated_data["quantity"]
		unit_price = bottle_type.price_mru
		total_price = unit_price * quantity
		instance = serializer.save(
			client=client,
			unit_price_mru=unit_price,
			total_price_mru=total_price,
			status=ClientOrder.PENDING,
		)
		ActivityLog.objects.create(
			user=getattr(self.request, "user", None),
			model_name=ClientOrder._meta.label,
			object_id=str(instance.pk),
			action=ActivityLog.ACTION_CREATE,
			description="Création de commande client (mobile)",
			data={
				"client_id": client.id,
				"bottle_type_id": bottle_type.id,
				"quantity": quantity,
				"unit_price_mru": str(unit_price),
				"total_price_mru": str(total_price),
			},
		)
		return instance


class DriverOrderViewSet(mixins.ListModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
	"""Vue dédiée aux chauffeurs pour consulter et marquer les commandes comme livrées.

	- LIST: retourne les commandes encore à livrer (pas en statut DELIVERED ou CANCELLED).
	- UPDATE (PATCH): permet au chauffeur de marquer une commande comme livrée.
	"""

	serializer_class = ClientOrderSerializer

	def get_driver(self):
		user = getattr(self.request, "user", None)
		if not user or not user.is_authenticated:
			raise PermissionDenied("Authentification requise.")
		from .models import Driver as DriverModel  # avoid circular import alias

		try:
			return user.driver_profile
		except DriverModel.DoesNotExist:
			raise PermissionDenied("Seuls les comptes chauffeurs peuvent utiliser cette API.")

	def get_queryset(self):
		# S'assure que l'utilisateur est bien un chauffeur
		self.get_driver()
		from .models import ClientOrder as ClientOrderModel  # alias local

		return (
			ClientOrderModel.objects.select_related("client", "bottle_type")
			.filter(status__in=[ClientOrderModel.PENDING, ClientOrderModel.VALIDATED])
			.order_by("-created_at")
		)

	def partial_update(self, request, *args, **kwargs):
		"""Permet à un chauffeur de marquer une commande comme livrée.

		On force le statut à DELIVERED et on renseigne delivered_at / delivered_by.
		"""

		driver = self.get_driver()
		from django.utils import timezone
		from .models import ClientOrder as ClientOrderModel

		instance = self.get_object()
		if instance.status in [ClientOrderModel.CANCELLED, ClientOrderModel.DELIVERED]:
			return Response(
				{"detail": "Cette commande ne peut plus être livrée."},
				status=status.HTTP_400_BAD_REQUEST,
			)

		instance.status = ClientOrderModel.DELIVERED
		instance.delivered_at = timezone.now()
		instance.delivered_by = driver
		instance.save(update_fields=["status", "delivered_at", "delivered_by", "updated_at"])

		# Journaliser dans ActivityLog
		try:
			ActivityLog.objects.create(
				user=request.user,
				model_name=ClientOrderModel._meta.label,
				object_id=str(instance.pk),
				action=ActivityLog.ACTION_UPDATE,
				description=f"Commande livrée par {driver.name}",
				data={
					"status": instance.status,
					"delivered_by_driver_id": driver.id,
					"delivered_by_driver_name": driver.name,
					"delivered_at": instance.delivered_at.isoformat(),
				},
			)
		except Exception:
			pass

		serializer = self.get_serializer(instance)
		return Response(serializer.data)


class ClientPaymentViewSet(mixins.CreateModelMixin, mixins.ListModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
	serializer_class = ClientSelfPaymentSerializer

	def _snapshot_instance(self, instance):
		"""Retourne un dict simple des champs de base de l'instance (sans M2M)."""
		if instance is None:
			return {}
		data = {}
		for field in instance._meta.fields:
			name = field.name
			try:
				value = getattr(instance, name)
			except Exception:
				continue
			# Pour les FK, stocker la valeur brute (pk) plutôt que l'objet complet
			if hasattr(value, "pk") and not isinstance(value, (str, int, float, bool)):
				data[name] = getattr(value, "pk", None)
			else:
				data[name] = value
		return data

	def _build_changes(self, before: dict, after: dict) -> dict:
		"""Construit un dict des champs modifiés: {field: {old, new}}."""
		changes = {}
		ignored = {"id", "pk", "created_at", "updated_at"}
		for field, old in before.items():
			if field in ignored:
				continue
			new = after.get(field)
			if old != new:
				changes[field] = {"old": old, "new": new}
		return changes

	def _log(self, instance, action: str, description: str = "", extra_data: dict | None = None):
		"""Journalise une action dans ActivityLog sans casser l'API en cas d'erreur."""
		try:
			if not description:
				model_verbose = getattr(instance._meta, "verbose_name", instance.__class__.__name__)
				obj_id = getattr(instance, "pk", None)
				base = f"{model_verbose}"
				if obj_id is not None:
					base = f"{base} #{obj_id}"
				if action == ActivityLog.ACTION_CREATE:
					description = f"Création de {base}"
				elif action == ActivityLog.ACTION_UPDATE:
					description = f"Mise à jour de {base}"
				elif action == ActivityLog.ACTION_DELETE:
					description = f"Suppression de {base}"
				else:
					description = f"Action {action} sur {base}"
		except Exception:
			pass

		try:
			ActivityLog.objects.create(
				user=getattr(self.request, "user", None),
				model_name=instance._meta.label,
				object_id=str(getattr(instance, "pk", "")),
				action=action,
				description=description,
				data=extra_data or None,
			)
		except Exception:
			# Ne jamais casser l'API à cause de la journalisation
			pass

	def get_client(self):
		user = getattr(self.request, "user", None)
		if not user or not user.is_authenticated:
			raise PermissionDenied("Seuls les comptes clients peuvent créer des demandes de paiement.")
		from .models import Client  # import local to avoid circular issues
		try:
			return user.client_profile
		except Client.DoesNotExist:
			raise PermissionDenied("Seuls les comptes clients peuvent créer des demandes de paiement.")

	def get_queryset(self):
		client = self.get_client()
		return Payment.objects.filter(client=client).order_by("-created_at")

	def perform_create(self, serializer):
		client = self.get_client()
		instance = serializer.save(client=client, status=Payment.PENDING)
		PaymentStatusHistory.objects.create(
			payment=instance,
			previous_status=None,
			new_status=Payment.PENDING,
			changed_by=getattr(self.request, "user", None),
			note="Création de la demande de paiement (client)",
		)
		ActivityLog.objects.create(
			user=getattr(self.request, "user", None),
			model_name=Payment._meta.label,
			object_id=str(instance.pk),
			action=ActivityLog.ACTION_CREATE,
			description="Création de paiement en attente (client mobile)",
			data={"amount_mru": str(instance.amount_mru), "client_id": client.id},
		)
		return instance

	def perform_update(self, serializer):
		payment = self.get_object()
		old_status = payment.status
		before = self._snapshot_instance(payment)
		# Laisser DRF appliquer les champs (receipt_image, method, ...)
		instance = serializer.save()
		new_status = instance.status

		# Si un reçu vient d'être ajouté pour la première fois et que le statut était pending,
		# forcer le passage en PENDING_ADMIN
		if (
			old_status == Payment.PENDING
			and instance.receipt_image is not None
			and not payment.receipt_image  # avant la sauvegarde, pas de reçu
		):
			instance.status = Payment.PENDING_ADMIN
			instance.save(update_fields=["status"])
			new_status = instance.status
		after = self._snapshot_instance(instance)
		changes = self._build_changes(before, after)
		changes_data = {"changes": changes} if changes else None

		if old_status != new_status:
			user = getattr(self.request, "user", None)
			# Passage en VALIDATED / REJECTED: réservé à la finance / superadmin
			if new_status in (Payment.VALIDATED, Payment.REJECTED):
				if not (user and (user.is_superuser or user.has_perm("core.can_validate_payments"))):
					raise PermissionDenied("Seul un utilisateur financier peut valider ou rejeter un paiement.")
				note = "Changement de statut via l'API (finance)"
			# Passage en PENDING_ADMIN après dépôt du reçu: effectué par le client
			elif new_status == Payment.PENDING_ADMIN:
				note = "Envoi du reçu par le client"
			else:
				note = "Changement de statut"

			PaymentStatusHistory.objects.create(
				payment=instance,
				previous_status=old_status,
				new_status=new_status,
				changed_by=user,
				note=note,
			)
			desc = f"Changement de statut {old_status} -> {new_status}"
			if changes:
				parts = []
				for field, vals in changes.items():
					parts.append(f"{field}: '{vals['old']}' -> '{vals['new']}'")
				fields_str = "; ".join(parts)
				desc = f"{desc} | Champs modifiés: {fields_str}"
			self._log(
				instance,
				ActivityLog.ACTION_UPDATE,
				desc,
				extra_data=changes_data,
			)
		else:
			# Mise à jour classique sans changement de statut
			desc = ""
			if changes:
				parts = []
				for field, vals in changes.items():
					parts.append(f"{field}: '{vals['old']}' -> '{vals['new']}'")
				fields_str = "; ".join(parts)
				desc = f"Champs modifiés: {fields_str}"
			self._log(instance, ActivityLog.ACTION_UPDATE, description=desc, extra_data=changes_data)

		return instance


class GasBottleTypeViewSet(AuditedModelViewSet):
	queryset = GasBottleType.objects.all().order_by("capacity_kg")
	serializer_class = GasBottleTypeSerializer


class ClientBottleBalanceViewSet(viewsets.ReadOnlyModelViewSet):
	queryset = ClientBottleBalance.objects.select_related("client", "bottle_type").all()
	serializer_class = ClientBottleBalanceSerializer


class WarehouseViewSet(AuditedModelViewSet):
	queryset = Warehouse.objects.all().order_by("name")
	serializer_class = WarehouseSerializer


class WarehouseBottleStockViewSet(AuditedModelViewSet):
	queryset = WarehouseBottleStock.objects.select_related("warehouse", "bottle_type").all()
	serializer_class = WarehouseBottleStockSerializer


class BusBottleStockViewSet(AuditedModelViewSet):
	queryset = BusBottleStock.objects.select_related("bus", "bottle_type").all()
	serializer_class = BusBottleStockSerializer


class GeofenceZoneViewSet(AuditedModelViewSet):
	queryset = GeofenceZone.objects.all().order_by("name")
	serializer_class = GeofenceZoneSerializer


class BusAlertViewSet(viewsets.ReadOnlyModelViewSet):
	queryset = BusAlert.objects.select_related("bus", "position").all().order_by("-created_at")
	serializer_class = BusAlertSerializer


class PaymentStatusHistoryViewSet(viewsets.ReadOnlyModelViewSet):
	queryset = PaymentStatusHistory.objects.select_related("payment", "changed_by", "payment__client").all().order_by(
		"-created_at"
	)
	serializer_class = PaymentStatusHistorySerializer


class ActivityLogViewSet(viewsets.ReadOnlyModelViewSet):
	queryset = ActivityLog.objects.select_related("user").all().order_by("-created_at")
	serializer_class = ActivityLogSerializer

	def get_queryset(self):
		qs = super().get_queryset()
		request = getattr(self, "request", None)
		if not request:
			return qs
		model_name = request.query_params.get("model") or None
		action = request.query_params.get("action") or None
		username = request.query_params.get("user") or None
		if model_name:
			qs = qs.filter(model_name__iexact=model_name)
		if action:
			qs = qs.filter(action=action)
		if username:
			qs = qs.filter(user__username__icontains=username)
		return qs
 

def _user_can_access_dashboard(user):
	"""Droit pour utiliser le back-office Rimgaz (AdminLTE), sans ouvrir Django admin.

	Un utilisateur peut accéder au backoffice s'il est:
	- staff (is_staff=True), ou
	- financier (permission core.can_validate_payments).
	"""
	return bool(user and user.is_authenticated and (user.is_staff or user.has_perm("core.can_validate_payments")))


def backoffice_required(view_func):
	"""Décorateur pour les vues AdminLTE du back-office.

	Ne nécessite pas is_staff, contrairement à staff_member_required, mais
	laisse Django admin (/admin/) inchangé (toujours réservé aux staff).
	"""
	@login_required
	def _wrapped(request, *args, **kwargs):
		user = request.user
		if not _user_can_access_dashboard(user):
			from django.core.exceptions import PermissionDenied as DjangoPermissionDenied

			raise DjangoPermissionDenied("Vous n'avez pas accès au back-office.")
		return view_func(request, *args, **kwargs)

	return _wrapped


@backoffice_required
def admin_dashboard(request):
	"""Dashboard HTML AdminLTE avec carte en temps réel."""
	return render(request, "core/admin_dashboard.html")


@backoffice_required
def dashboard_clients(request):
	return render(request, "core/dashboard_clients.html")


@backoffice_required
def dashboard_buses(request):
	return render(request, "core/dashboard_buses.html")


@backoffice_required
def dashboard_drivers(request):
	return render(request, "core/dashboard_drivers.html")


@backoffice_required
def dashboard_tours(request):
	return render(request, "core/dashboard_tours.html")


@backoffice_required
def dashboard_payments(request):
	return render(request, "core/dashboard_payments.html")


@backoffice_required
def dashboard_wallets(request):
	return render(request, "core/dashboard_wallets.html")


@backoffice_required
def dashboard_payment_history(request):
	return render(request, "core/dashboard_payment_history.html")


@backoffice_required
def dashboard_client_orders(request):
	return render(request, "core/dashboard_client_orders.html")


@backoffice_required
def dashboard_bottle_types(request):
	return render(request, "core/dashboard_bottle_types.html")


@backoffice_required
def dashboard_bottle_balances(request):
	return render(request, "core/dashboard_bottle_balances.html")


@backoffice_required
def dashboard_activity_log(request):
	return render(request, "core/dashboard_activity_log.html")


@backoffice_required
def dashboard_bus_positions(request):
	return render(request, "core/dashboard_bus_positions.html")


@backoffice_required
def dashboard_warehouses(request):
	return render(request, "core/dashboard_warehouses.html")


@backoffice_required
def dashboard_warehouse_stocks(request):
	return render(request, "core/dashboard_warehouse_stocks.html")


@backoffice_required
def dashboard_bus_stocks(request):
	return render(request, "core/dashboard_bus_stocks.html")


@backoffice_required
def dashboard_bus_alerts(request):
	return render(request, "core/dashboard_bus_alerts.html")


@backoffice_required
def dashboard_geofences(request):
	return render(request, "core/dashboard_geofences.html")


@backoffice_required
def dashboard_users(request):
	return render(request, "core/dashboard_users.html")

