from django.db import models
from django.conf import settings
from django.contrib.auth import get_user_model


class TimeStampedModel(models.Model):
	created_at = models.DateTimeField(auto_now_add=True)
	updated_at = models.DateTimeField(auto_now=True)

	class Meta:
		abstract = True


class Client(TimeStampedModel):
	ACTIVE = "active"
	SUSPENDED = "suspended"
	LATE = "late"

	STATUS_CHOICES = [
		(ACTIVE, "Actif"),
		(SUSPENDED, "Suspendu"),
		(LATE, "En retard de paiement"),
	]

	FRENCH = "fr"
	ARABIC = "ar"

	LANGUAGE_CHOICES = [
		(FRENCH, "Français"),
		(ARABIC, "العربية"),
	]

	name = models.CharField(max_length=255)
	phone = models.CharField(max_length=50, unique=True)
	whatsapp = models.CharField(max_length=50, blank=True)
	address = models.TextField(blank=True)
	gps_latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
	gps_longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
	client_type = models.CharField(max_length=50, default="household")
	language = models.CharField(max_length=5, choices=LANGUAGE_CHOICES, default=FRENCH)
	status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=ACTIVE)
	user = models.OneToOneField(
		settings.AUTH_USER_MODEL,
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
		related_name="client_profile",
	)

	def __str__(self) -> str:
		return f"{self.name} ({self.phone})"


class Bus(TimeStampedModel):
	name = models.CharField(max_length=100)
	plate_number = models.CharField(max_length=50, blank=True)
	capacity = models.PositiveIntegerField(null=True, blank=True)
	max_speed_kmh = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True)

	def __str__(self) -> str:
		return self.name


class Driver(TimeStampedModel):
	name = models.CharField(max_length=255)
	phone = models.CharField(max_length=50, unique=True)
	bus = models.OneToOneField(Bus, on_delete=models.SET_NULL, null=True, blank=True, related_name="driver")
	user = models.OneToOneField(
		settings.AUTH_USER_MODEL,
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
		related_name="driver_profile",
	)

	def __str__(self) -> str:
		return self.name

	def save(self, *args, **kwargs):
		"""Lors de la création d'un chauffeur, générer automatiquement un utilisateur.

		- username = première lettre du nom + 4 premiers chiffres du téléphone
		- mot de passe = "rimgaz1234"
		"""
		UserModel = get_user_model()
		if self.user is None and self.name and self.phone:
			base_name = self.name.strip()
			base_phone = "".join(ch for ch in self.phone if ch.isdigit())
			if base_name:
				first_letter = base_name[0].lower()
			else:
				first_letter = "d"
			prefix_phone = base_phone[:4] if base_phone else "0000"
			base_username = f"{first_letter}{prefix_phone}"
			username = base_username
			suffix = 1
			while UserModel.objects.filter(username=username).exists():
				username = f"{base_username}{suffix}"
				suffix += 1

			user = UserModel(username=username, is_active=True)
			user.set_password("rimgaz1234")
			user.save()
			self.user = user

		return super().save(*args, **kwargs)


class Warehouse(TimeStampedModel):
	name = models.CharField(max_length=100)
	address = models.CharField(max_length=255, blank=True)
	gps_latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
	gps_longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

	def __str__(self) -> str:
		return self.name


class GasBottleType(TimeStampedModel):
	name = models.CharField(max_length=100)
	capacity_kg = models.DecimalField(max_digits=5, decimal_places=2)
	price_mru = models.DecimalField(max_digits=12, decimal_places=2)
	deposit_mru = models.DecimalField(max_digits=12, decimal_places=2, default=0)

	def __str__(self) -> str:
		return f"{self.name} ({self.capacity_kg}kg)"


class ClientBottleBalance(TimeStampedModel):
	client = models.ForeignKey(Client, on_delete=models.CASCADE, related_name="bottle_balances")
	bottle_type = models.ForeignKey(GasBottleType, on_delete=models.CASCADE)
	quantity = models.IntegerField(default=0)

	class Meta:
		unique_together = ("client", "bottle_type")

	def __str__(self) -> str:
		return f"{self.client} - {self.bottle_type}: {self.quantity}"


class WarehouseBottleStock(TimeStampedModel):
	warehouse = models.ForeignKey(Warehouse, on_delete=models.CASCADE, related_name="stocks")
	bottle_type = models.ForeignKey(GasBottleType, on_delete=models.CASCADE)
	quantity = models.IntegerField(default=0)

	class Meta:
		unique_together = ("warehouse", "bottle_type")

	def __str__(self) -> str:
		return f"{self.warehouse} - {self.bottle_type}: {self.quantity}"


class BusBottleStock(TimeStampedModel):
	bus = models.ForeignKey(Bus, on_delete=models.CASCADE, related_name="stocks")
	bottle_type = models.ForeignKey(GasBottleType, on_delete=models.CASCADE)
	quantity = models.IntegerField(default=0)

	class Meta:
		unique_together = ("bus", "bottle_type")

	def __str__(self) -> str:
		return f"{self.bus} - {self.bottle_type}: {self.quantity}"


class Wallet(TimeStampedModel):
	client = models.OneToOneField(Client, on_delete=models.CASCADE, related_name="wallet")
	balance_mru = models.DecimalField(max_digits=14, decimal_places=2, default=0)

	def __str__(self) -> str:
		return f"Wallet {self.client} - {self.balance_mru} MRU"


class Payment(TimeStampedModel):
	PENDING = "pending"
	PENDING_ADMIN = "pending_admin"
	VALIDATED = "validated"
	REJECTED = "rejected"

	STATUS_CHOICES = [
		(PENDING, "En attente"),
		(PENDING_ADMIN, "En attente administration"),
		(VALIDATED, "Validé"),
		(REJECTED, "Rejeté"),
	]

	METHOD_BANKILY = "bankily"
	METHOD_MASRVI = "masrvi"
	METHOD_SEDAD = "sedad"
	METHOD_CLICK = "click"
	OTHER_METHOD = "autre"

	METHOD_CHOICES = [
		(METHOD_BANKILY, "Bankily"),
		(METHOD_MASRVI, "Masrvi"),
		(METHOD_SEDAD, "Sedad"),
		(METHOD_CLICK, "Click"),
		(OTHER_METHOD, "Autre"),
	]

	client = models.ForeignKey(Client, on_delete=models.CASCADE, related_name="payments")
	order = models.ForeignKey("ClientOrder", on_delete=models.SET_NULL, null=True, blank=True, related_name="payments")
	amount_mru = models.DecimalField(max_digits=14, decimal_places=2)
	method = models.CharField(max_length=50, choices=METHOD_CHOICES, blank=True)
	receipt_image = models.ImageField(upload_to="receipts/", null=True, blank=True)
	status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=PENDING)
	rejection_reason = models.TextField(blank=True)

	def __str__(self) -> str:
		return f"Payment {self.id} - {self.client} - {self.amount_mru} MRU"

	class Meta:
		permissions = [
			("can_validate_payments", "Peut valider ou rejeter les paiements"),
		]


class Tour(TimeStampedModel):
	date = models.DateField()
	sector = models.CharField(max_length=255, blank=True)
	bus = models.ForeignKey(Bus, on_delete=models.CASCADE, related_name="tours")
	driver = models.ForeignKey(Driver, on_delete=models.SET_NULL, null=True, blank=True, related_name="tours")

	def __str__(self) -> str:
		return f"Tournée {self.date} - {self.bus}"


class TourStop(TimeStampedModel):
	PENDING = "pending"
	COMPLETED = "completed"
	SKIPPED = "skipped"

	STATUS_CHOICES = [
		(PENDING, "À visiter"),
		(COMPLETED, "Visité"),
		(SKIPPED, "Non visité"),
	]

	tour = models.ForeignKey(Tour, on_delete=models.CASCADE, related_name="stops")
	client = models.ForeignKey(Client, on_delete=models.CASCADE, related_name="tour_stops")
	order_index = models.PositiveIntegerField()
	status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=PENDING)
	delivered_bottles = models.IntegerField(default=0)
	returned_bottles = models.IntegerField(default=0)

	class Meta:
		ordering = ["order_index"]

	def __str__(self) -> str:
		return f"{self.tour} - {self.client} ({self.status})"


class BusPosition(TimeStampedModel):
	STATUS_ON_TOUR = "on_tour"
	STATUS_PAUSED = "paused"
	STATUS_RETURNING = "returning"
	STATUS_OFFLINE = "offline"

	STATUS_CHOICES = [
		(STATUS_ON_TOUR, "En tournée"),
		(STATUS_PAUSED, "En pause"),
		(STATUS_RETURNING, "Retour dépôt"),
		(STATUS_OFFLINE, "Hors ligne"),
	]

	bus = models.ForeignKey(Bus, on_delete=models.CASCADE, related_name="positions")
	tour = models.ForeignKey(Tour, on_delete=models.SET_NULL, null=True, blank=True, related_name="positions")
	latitude = models.DecimalField(max_digits=9, decimal_places=6)
	longitude = models.DecimalField(max_digits=9, decimal_places=6)
	status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_ON_TOUR)
	speed_kmh = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True)

	class Meta:
		indexes = [
			models.Index(fields=["bus", "created_at"]),
		]

	def __str__(self) -> str:
		return f"{self.bus} @ {self.latitude},{self.longitude}"


class GeofenceZone(TimeStampedModel):
	name = models.CharField(max_length=100)
	center_latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
	center_longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
	radius_meters = models.PositiveIntegerField(help_text="Rayon du périmètre en mètres", null=True, blank=True)
	polygon = models.JSONField(null=True, blank=True, help_text="Liste de points [lat, lon] décrivant un polygone")
	is_active = models.BooleanField(default=True)

	def __str__(self) -> str:
		return f"{self.name} ({self.radius_meters}m)"


class BusAlert(TimeStampedModel):
	TYPE_SPEED = "speed"
	TYPE_GEOFENCE = "geofence"

	ALERT_TYPE_CHOICES = [
		(TYPE_SPEED, "Vitesse"),
		(TYPE_GEOFENCE, "Geofencing"),
	]

	bus = models.ForeignKey(Bus, on_delete=models.CASCADE, related_name="alerts")
	position = models.ForeignKey(BusPosition, on_delete=models.CASCADE, related_name="alerts")
	alert_type = models.CharField(max_length=20, choices=ALERT_TYPE_CHOICES)
	message = models.TextField()
	is_resolved = models.BooleanField(default=False)

	class Meta:
		ordering = ["-created_at"]

	def __str__(self) -> str:
		return f"{self.bus} - {self.alert_type} - {self.created_at}"


class ClientOrder(TimeStampedModel):
	PENDING = "pending"
	VALIDATED = "validated"
	CANCELLED = "cancelled"
	DELIVERED = "delivered"

	STATUS_CHOICES = [
		(PENDING, "En attente"),
		(VALIDATED, "Validée"),
		(DELIVERED, "Livrée"),
		(CANCELLED, "Annulée"),
	]

	client = models.ForeignKey(Client, on_delete=models.CASCADE, related_name="orders")
	bottle_type = models.ForeignKey(GasBottleType, on_delete=models.PROTECT, related_name="orders")
	quantity = models.PositiveIntegerField()
	unit_price_mru = models.DecimalField(max_digits=12, decimal_places=2)
	total_price_mru = models.DecimalField(max_digits=14, decimal_places=2)
	status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=PENDING)
	delivered_at = models.DateTimeField(null=True, blank=True)
	delivered_by = models.ForeignKey(
		Driver,
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
		related_name="delivered_orders",
	)

	class Meta:
		ordering = ["-created_at"]

	def __str__(self) -> str:
		return f"Commande {self.id} - {self.client} - {self.quantity} x {self.bottle_type}"


class PaymentStatusHistory(TimeStampedModel):
	payment = models.ForeignKey(Payment, on_delete=models.CASCADE, related_name="status_history")
	previous_status = models.CharField(max_length=20, choices=Payment.STATUS_CHOICES, null=True, blank=True)
	new_status = models.CharField(max_length=20, choices=Payment.STATUS_CHOICES)
	changed_by = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
		related_name="payment_status_changes",
	)
	note = models.TextField(blank=True)

	class Meta:
		ordering = ["-created_at"]

	def __str__(self) -> str:
		return f"Payment {self.payment_id}: {self.previous_status} -> {self.new_status}"


class ActivityLog(TimeStampedModel):
	ACTION_CREATE = "create"
	ACTION_UPDATE = "update"
	ACTION_DELETE = "delete"
	ACTION_OTHER = "other"

	ACTION_CHOICES = [
		(ACTION_CREATE, "Création"),
		(ACTION_UPDATE, "Modification"),
		(ACTION_DELETE, "Suppression"),
		(ACTION_OTHER, "Autre"),
	]

	user = models.ForeignKey(
		settings.AUTH_USER_MODEL,
		on_delete=models.SET_NULL,
		null=True,
		blank=True,
		related_name="activity_logs",
	)
	model_name = models.CharField(max_length=100)
	object_id = models.CharField(max_length=50, blank=True)
	action = models.CharField(max_length=20, choices=ACTION_CHOICES)
	description = models.TextField(blank=True)
	data = models.JSONField(null=True, blank=True)

	class Meta:
		ordering = ["-created_at"]

	def __str__(self) -> str:
		return f"{self.model_name}({self.object_id}) - {self.action}"

