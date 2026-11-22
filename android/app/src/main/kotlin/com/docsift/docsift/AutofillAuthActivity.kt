package com.docsift.docsift

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * Ephemeral `FLAG_SECURE` authentication & account-selection host invoked when
 * the user taps a DocSift Autofill chip/dropdown item in an external app.
 */
class AutofillAuthActivity : FragmentActivity() {

    companion object {
        const val EXTRA_MODE = "extra_mode"
        const val MODE_SINGLE = "single"
        const val MODE_PICKER = "picker"

        const val EXTRA_CREDENTIAL_ID = "extra_credential_id"
        const val EXTRA_USERNAME_ID = "extra_username_id"
        const val EXTRA_PASSWORD_ID = "extra_password_id"
        const val EXTRA_TARGET_PACKAGE = "extra_target_package"
        const val EXTRA_WEB_DOMAIN = "extra_web_domain"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )

        authenticateUser {
            onAuthenticated()
        }
    }

    private fun authenticateUser(onSuccess: () -> Unit) {
        val biometricManager = BiometricManager.from(this)
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG or
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL

        val canAuth = biometricManager.canAuthenticate(authenticators)
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            // Device has no enrolled biometrics or lockscreen credential configured
            onSuccess()
            return
        }

        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(
            this,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    super.onAuthenticationSucceeded(result)
                    onSuccess()
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    super.onAuthenticationError(errorCode, errString)
                    cancelAndFinish()
                }
            }
        )

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("DocSift Autofill")
            .setSubtitle("Verify identity to fill saved login")
            .setAllowedAuthenticators(authenticators)
            .build()

        prompt.authenticate(promptInfo)
    }

    private fun onAuthenticated() {
        val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_SINGLE
        val usernameId = readAutofillId(EXTRA_USERNAME_ID)
        val passwordId = readAutofillId(EXTRA_PASSWORD_ID)
        val targetPackage = intent.getStringExtra(EXTRA_TARGET_PACKAGE)
        val webDomain = intent.getStringExtra(EXTRA_WEB_DOMAIN)

        if (mode == MODE_SINGLE) {
            val credId = intent.getStringExtra(EXTRA_CREDENTIAL_ID)
            val entry = if (credId != null) {
                AutofillCredentialStore.getCredentialById(applicationContext, credId)
            } else {
                null
            }
            if (entry != null) {
                deliverDatasetAndFinish(entry, usernameId, passwordId)
            } else {
                cancelAndFinish()
            }
            return
        }

        // MODE_PICKER: Let user freely select from all saved vault logins
        val allEntries = AutofillCredentialStore.loadAllCredentials(applicationContext)
        if (allEntries.isEmpty()) {
            cancelAndFinish()
            return
        }

        val labels = allEntries.map { entry ->
            if (entry.username.isNotBlank()) {
                "${entry.title} (${entry.username})"
            } else {
                entry.title
            }
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Select DocSift Account")
            .setItems(labels) { _, which ->
                val chosen = allEntries[which]
                AutofillCredentialStore.bindPackageToCredential(
                    context = applicationContext,
                    credentialId = chosen.id,
                    packageName = targetPackage,
                    webDomain = webDomain,
                )
                deliverDatasetAndFinish(chosen, usernameId, passwordId)
            }
            .setNegativeButton("Cancel") { _, _ ->
                cancelAndFinish()
            }
            .setOnCancelListener {
                cancelAndFinish()
            }
            .show()
    }

    private fun deliverDatasetAndFinish(
        entry: AutofillEntry,
        usernameId: AutofillId?,
        passwordId: AutofillId?,
    ) {
        val presentation = RemoteViews(packageName, R.layout.autofill_dataset_item).apply {
            setTextViewText(R.id.autofill_title, entry.username.ifBlank { entry.title })
            setTextViewText(R.id.autofill_subtitle, entry.title)
        }

        @Suppress("DEPRECATION")
        val datasetBuilder = Dataset.Builder(presentation)
        var populatedAny = false

        if (usernameId != null && entry.username.isNotEmpty()) {
            @Suppress("DEPRECATION")
            datasetBuilder.setValue(
                usernameId,
                AutofillValue.forText(entry.username),
                presentation,
            )
            populatedAny = true
        }
        if (passwordId != null && entry.password.isNotEmpty()) {
            @Suppress("DEPRECATION")
            datasetBuilder.setValue(
                passwordId,
                AutofillValue.forText(entry.password),
                presentation,
            )
            populatedAny = true
        }

        if (!populatedAny) {
            cancelAndFinish()
            return
        }

        val replyIntent = Intent().apply {
            putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, datasetBuilder.build())
        }
        setResult(Activity.RESULT_OK, replyIntent)
        finish()
    }

    private fun readAutofillId(key: String): AutofillId? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(key, AutofillId::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(key)
        }
    }

    private fun cancelAndFinish() {
        setResult(Activity.RESULT_CANCELED)
        finish()
    }
}

