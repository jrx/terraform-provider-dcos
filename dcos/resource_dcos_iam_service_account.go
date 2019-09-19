package dcos

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/dcos/client-go/dcos"
	"github.com/hashicorp/terraform/helper/schema"
)

func resourceDcosIAMServiceAccount() *schema.Resource {
	return &schema.Resource{
		Create: resourceDcosIAMServiceAccountCreate,
		Read:   resourceDcosIAMServiceAccountRead,
		Update: resourceDcosIAMServiceAccountUpdate,
		Delete: resourceDcosIAMServiceAccountDelete,
		// Importer: &schema.ResourceImporter{
		// 	State: schema.ImportStatePassthrough,
		// },

		SchemaVersion: 1,
		Timeouts: &schema.ResourceTimeout{
			Create: schema.DefaultTimeout(10 * time.Minute),
			Update: schema.DefaultTimeout(10 * time.Minute),
			Delete: schema.DefaultTimeout(20 * time.Minute),
		},

		Schema: map[string]*schema.Schema{
			"uid": {
				Type:        schema.TypeString,
				Required:    true,
				ForceNew:    true,
				Description: "ID of the account is used by default",
			},
			"description": {
				Type:        schema.TypeString,
				Required:    true,
				ForceNew:    false,
				Description: "Description of the newly created service account",
			},
			"public_key": {
				Type:        schema.TypeString,
				Optional:    true,
				ForceNew:    true,
				Description: "Path to public key to use",
			},
		},
	}
}

func iamUserCreateFromResourceData(d *schema.ResourceData) (dcos.IamUserCreate, error) {
	iamUserCreate := dcos.IamUserCreate{}

	if publicKey, pkOK := d.GetOk("public_key"); pkOK {
		iamUserCreate.PublicKey = publicKey.(string)
	}

	if description, ok := d.GetOk("description"); ok {
		iamUserCreate.Description = description.(string)
	}

	if password, ok := d.GetOk("password"); ok {
		iamUserCreate.Password = password.(string)
	}

	return iamUserCreate, nil
}

func resourceDcosIAMServiceAccountCreate(d *schema.ResourceData, meta interface{}) error {
	client := meta.(*ProviderState).Client
	ctx := context.TODO()

	uid := d.Get("uid").(string)
	iamUserCreate, err := iamUserCreateFromResourceData(d)

	if err != nil {
		return err
	}

	resp, err := client.IAM.CreateUser(ctx, uid, iamUserCreate)

	log.Printf("[TRACE] IAM.CreateUser - %v", resp)

	if err != nil {
		return err
	}

	d.SetId(uid)

	return nil
}

func resourceDcosIAMServiceAccountRead(d *schema.ResourceData, meta interface{}) error {
	client := meta.(*ProviderState).Client
	ctx := context.TODO()

	uid := d.Id()

	user, resp, err := client.IAM.GetUser(ctx, uid)

	log.Printf("[TRACE] IAM.GetUser - %v", resp)

	if resp != nil && (resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusBadRequest) {
		log.Printf("[INFO] IAM.GetUser - %s not found", uid)
		d.SetId("")
		return nil
	}

	if err != nil {
		return err
	}

	d.Set("description", user.Description)
	d.Set("public_key", user.PublicKey)
	d.SetId(uid)

	return nil
}

func resourceDcosIAMServiceAccountUpdate(d *schema.ResourceData, meta interface{}) error {
	client := meta.(*ProviderState).Client
	ctx := context.TODO()

	uid := d.Id()
	iamUserUpdate := dcos.IamUserUpdate{}

	if description, ok := d.GetOk("description"); ok {
		iamUserUpdate.Description = description.(string)
	}

	resp, err := client.IAM.UpdateUser(ctx, uid, iamUserUpdate)

	log.Printf("[TRACE] IAM.UpdateUser - %v", resp)

	if err != nil {
		return err
	}

	return resourceDcosIAMServiceAccountRead(d, meta)
}

func resourceDcosIAMServiceAccountDelete(d *schema.ResourceData, meta interface{}) error {
	client := meta.(*ProviderState).Client
	ctx := context.TODO()

	resp, err := client.IAM.DeleteUser(ctx, d.Id())

	if resp != nil && resp.StatusCode == http.StatusNotFound {
		d.SetId("")
		return nil
	}

	if err != nil {
		return err
	}

	d.SetId("")

	return nil
}
