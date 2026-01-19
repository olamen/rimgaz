from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import Client, Driver, ClientOrder, Payment, ActivityLog


User = get_user_model()


def _generate_username(prefix: str, phone: str | None) -> str:
	clean_phone = (phone or "").strip().replace(" ", "")
	base_suffix = clean_phone if clean_phone else "user"
	base = f"{prefix}{base_suffix}"
	username = base
	counter = 1
	while User.objects.filter(username=username).exists():
		username = f"{base}_{counter}"
		counter += 1
	return username


def _create_user_for_instance(instance, group_name: str, prefix: str):
	if instance.user is not None:
		return

	phone = getattr(instance, "phone", None)
	username = _generate_username(prefix, phone)
	password = "rimgaz1234"
	user = User.objects.create_user(
		username=username,
		password=password,
		is_staff=False,
		is_superuser=False,
	)
	group, _ = Group.objects.get_or_create(name=group_name)
	user.groups.add(group)
	instance.user = user
	instance.save(update_fields=["user"])


@receiver(post_save, sender=Client)
def create_user_for_client(sender, instance: Client, created: bool, **kwargs):
	if created and instance.id:
		_create_user_for_instance(instance, group_name="clients", prefix="rimgaz_client_")


@receiver(post_save, sender=Driver)
def create_user_for_driver(sender, instance: Driver, created: bool, **kwargs):
	if created and instance.id:
		_create_user_for_instance(instance, group_name="drivers", prefix="rimgaz_driver_")


@receiver(post_save, sender=ClientOrder)
def create_payment_for_validated_order(sender, instance: ClientOrder, created: bool, **kwargs):
	"""When a client order is validated, automatically create a pending Payment.

	This increments pending payments for finance and notifies the system that
	the client must now pay for the validated order.
	"""
	# Only act on updates, not on initial creation of the order
	if created:
		return

	# We only care about orders that are in VALIDATED status
	if instance.status != ClientOrder.VALIDATED:
		return

	# Avoid creating multiple payments for the same order
	if Payment.objects.filter(order=instance).exists():
		return

	payment = Payment.objects.create(
		client=instance.client,
		order=instance,
		amount_mru=instance.total_price_mru,
		method="",
		status=Payment.PENDING,
		rejection_reason="",
	)

	# Log the creation for audit / dashboards
	ActivityLog.objects.create(
		user=getattr(instance.client, "user", None),
		model_name=Payment._meta.label,
		object_id=str(payment.pk),
		action=ActivityLog.ACTION_CREATE,
		description=f"Création d'un paiement en attente pour la commande #{instance.id}",
		data={
			"order_id": instance.id,
			"client_id": instance.client.id,
			"amount_mru": str(payment.amount_mru),
		},
	)

