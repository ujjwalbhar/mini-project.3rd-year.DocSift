package com.docsift.docsift

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.widget.RemoteViews

class DocSiftAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val contexts = request.fillContexts
        if (contexts.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val latestStructure = contexts.last().structure
        val callingPackage = latestStructure.activityComponent?.packageName
        if (callingPackage.isNullOrBlank() || isExcludedPackage(callingPackage)) {
            callback.onSuccess(null)
            return
        }

        val parsed = parseStructure(latestStructure)
        val usernameId = parsed.usernameId
        val passwordId = parsed.passwordId

        // Only respond on genuine login / registration screens
        if (usernameId == null && passwordId == null) {
            callback.onSuccess(null)
            return
        }
        // Avoid offering login autofill on standalone non-password text inputs (e.g. search bars)
        if (passwordId == null && !parsed.isExplicitLoginUsername) {
            callback.onSuccess(null)
            return
        }

        val responseBuilder = FillResponse.Builder()

        // Configure SaveInfo so Android prompts "Save to DocSift?" when creating new accounts
        if (passwordId != null) {
            val requiredIds = if (usernameId != null) {
                arrayOf(usernameId, passwordId)
            } else {
                arrayOf(passwordId)
            }
            val saveTypes = if (usernameId != null) {
                SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD
            } else {
                SaveInfo.SAVE_DATA_TYPE_PASSWORD
            }
            val saveInfo = SaveInfo.Builder(saveTypes, requiredIds)
                .setFlags(SaveInfo.FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE)
                .build()
            responseBuilder.setSaveInfo(saveInfo)
        }

        val matches = AutofillCredentialStore.findMatchingCredentials(
            context = applicationContext,
            packageName = callingPackage,
            webDomain = parsed.webDomain,
        )
        val allVaultEntries = AutofillCredentialStore.loadAllCredentials(applicationContext)

        var requestCodeSeed = (System.currentTimeMillis() and 0xFFFFFF).toInt()

        // 1. Add an individual Dataset row for EVERY matching account (Multi-Account Freedom!)
        for (entry in matches) {
            val titleText = entry.username.ifBlank { entry.title }
            val subtitleText = "${entry.title} · Biometric Autofill"
            val presentation = buildPresentation(titleText, subtitleText)

            val authIntent = Intent(this, AutofillAuthActivity::class.java).apply {
                putExtra(AutofillAuthActivity.EXTRA_MODE, AutofillAuthActivity.MODE_SINGLE)
                putExtra(AutofillAuthActivity.EXTRA_CREDENTIAL_ID, entry.id)
                putExtra(AutofillAuthActivity.EXTRA_USERNAME_ID, usernameId)
                putExtra(AutofillAuthActivity.EXTRA_PASSWORD_ID, passwordId)
                putExtra(AutofillAuthActivity.EXTRA_TARGET_PACKAGE, callingPackage)
                putExtra(AutofillAuthActivity.EXTRA_WEB_DOMAIN, parsed.webDomain)
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                requestCodeSeed++,
                authIntent,
                mutablePendingIntentFlags(),
            )

            @Suppress("DEPRECATION")
            val datasetBuilder = Dataset.Builder(presentation)
                .setAuthentication(pendingIntent.intentSender)
            if (usernameId != null) {
                @Suppress("DEPRECATION")
                datasetBuilder.setValue(usernameId, null, presentation)
            }
            if (passwordId != null) {
                @Suppress("DEPRECATION")
                datasetBuilder.setValue(passwordId, null, presentation)
            }
            responseBuilder.addDataset(datasetBuilder.build())
        }

        // 2. Also offer "Choose from DocSift Vault..." whenever vault has saved accounts
        if (allVaultEntries.isNotEmpty() && passwordId != null) {
            val pickerLabel = if (matches.isEmpty()) {
                "Autofill with DocSift Vault"
            } else {
                "Choose another DocSift account..."
            }
            val pickerSub = "${allVaultEntries.size} saved login${if (allVaultEntries.size == 1) "" else "s"} · Tap to select"
            val pickerPresentation = buildPresentation(pickerLabel, pickerSub)

            val pickerIntent = Intent(this, AutofillAuthActivity::class.java).apply {
                putExtra(AutofillAuthActivity.EXTRA_MODE, AutofillAuthActivity.MODE_PICKER)
                putExtra(AutofillAuthActivity.EXTRA_USERNAME_ID, usernameId)
                putExtra(AutofillAuthActivity.EXTRA_PASSWORD_ID, passwordId)
                putExtra(AutofillAuthActivity.EXTRA_TARGET_PACKAGE, callingPackage)
                putExtra(AutofillAuthActivity.EXTRA_WEB_DOMAIN, parsed.webDomain)
            }
            val pickerPending = PendingIntent.getActivity(
                this,
                requestCodeSeed++,
                pickerIntent,
                mutablePendingIntentFlags(),
            )

            @Suppress("DEPRECATION")
            val pickerDataset = Dataset.Builder(pickerPresentation)
                .setAuthentication(pickerPending.intentSender)
            if (usernameId != null) {
                @Suppress("DEPRECATION")
                pickerDataset.setValue(usernameId, null, pickerPresentation)
            }
            @Suppress("DEPRECATION")
            pickerDataset.setValue(passwordId, null, pickerPresentation)
            responseBuilder.addDataset(pickerDataset.build())
        }

        callback.onSuccess(responseBuilder.build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val contexts = request.fillContexts
        if (contexts.isEmpty()) {
            callback.onSuccess()
            return
        }

        var capturedUsername = ""
        var capturedPassword = ""
        var capturedDomain: String? = null
        var callingPackage: String? = null

        // Inspect all fillContexts so 2-step login/signup wizards (Email screen -> Password screen)
        // retain both the username from step 1 and the password from step 2.
        for (ctx in contexts) {
            val pkg = ctx.structure.activityComponent?.packageName
            if (!pkg.isNullOrBlank()) {
                callingPackage = pkg
            }
            val parsed = parseStructure(ctx.structure)
            if (!parsed.webDomain.isNullOrBlank()) {
                capturedDomain = parsed.webDomain
            }
            if (parsed.usernameValue.isNotBlank()) {
                capturedUsername = parsed.usernameValue
            }
            if (parsed.passwordValue.isNotBlank()) {
                capturedPassword = parsed.passwordValue
            }
        }

        if (callingPackage != null && isExcludedPackage(callingPackage)) {
            callback.onSuccess()
            return
        }

        // Ignore empty passwords or short numeric OTPs / PINs (4-6 digits)
        val trimmedPw = capturedPassword.trim()
        val isLikelyOtp = trimmedPw.length in 4..6 && trimmedPw.all { it.isDigit() }
        if (trimmedPw.isEmpty() || isLikelyOtp) {
            callback.onSuccess()
            return
        }

        val friendlyTitle = resolveFriendlyTitle(callingPackage, capturedDomain)
        AutofillCredentialStore.recordCapturedLogin(
            context = applicationContext,
            title = friendlyTitle,
            username = capturedUsername,
            password = capturedPassword,
            webDomain = capturedDomain,
            packageName = callingPackage,
        )

        callback.onSuccess()
    }

    private fun resolveFriendlyTitle(packageName: String?, webDomain: String?): String {
        val normDomain = AutofillCredentialStore.normalizeDomain(webDomain)
        if (normDomain.isNotEmpty()) {
            val brand = normDomain.substringBefore('.')
            return brand.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        }
        if (!packageName.isNullOrBlank()) {
            return try {
                val appInfo = packageManager.getApplicationInfo(packageName, 0)
                packageManager.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {
                packageName.substringAfterLast('.')
            }
        }
        return "Saved Login"
    }

    private fun buildPresentation(title: String, subtitle: String): RemoteViews {
        return RemoteViews(packageName, R.layout.autofill_dataset_item).apply {
            setTextViewText(R.id.autofill_title, title)
            setTextViewText(R.id.autofill_subtitle, subtitle)
        }
    }

    private fun mutablePendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_CANCEL_CURRENT
        } else {
            PendingIntent.FLAG_CANCEL_CURRENT
        }
    }

    private fun isExcludedPackage(pkg: String): Boolean {
        if (pkg == packageName) return true
        val lower = pkg.lowercase()
        return lower.startsWith("com.android.systemui") ||
            lower.contains("inputmethod") ||
            lower.contains("keyboard") ||
            lower.contains("launcher")
    }

    private data class ParsedLoginFields(
        var usernameId: AutofillId? = null,
        var passwordId: AutofillId? = null,
        var usernameValue: String = "",
        var passwordValue: String = "",
        var webDomain: String? = null,
        var isExplicitLoginUsername: Boolean = false,
    )

    private fun parseStructure(structure: AssistStructure): ParsedLoginFields {
        val out = ParsedLoginFields()
        val windowCount = structure.windowNodeCount
        for (i in 0 until windowCount) {
            val root = structure.getWindowNodeAt(i).rootViewNode
            traverseNode(root, out)
        }
        return out
    }

    private fun traverseNode(node: AssistStructure.ViewNode, out: ParsedLoginFields) {
        if (!node.webDomain.isNullOrBlank() && out.webDomain.isNullOrBlank()) {
            out.webDomain = node.webDomain
        }

        val autofillId = node.autofillId
        if (autofillId != null && node.autofillType != View.AUTOFILL_TYPE_NONE) {
            classifyInputNode(node, autofillId, out)
        }

        val childCount = node.childCount
        for (i in 0 until childCount) {
            traverseNode(node.getChildAt(i), out)
        }
    }

    private fun classifyInputNode(
        node: AssistStructure.ViewNode,
        autofillId: AutofillId,
        out: ParsedLoginFields,
    ) {
        val hints = node.autofillHints?.map { it.lowercase() } ?: emptyList()
        val idEntry = node.idEntry?.lowercase().orEmpty()
        val hintText = node.hint?.lowercase().orEmpty()
        val htmlAttrs = node.htmlInfo?.attributes
            ?.joinToString(" ") { "${it.first}=${it.second}".lowercase() }
            .orEmpty()
        val combinedMeta = "$idEntry $hintText $htmlAttrs ${hints.joinToString(" ")}"

        // Strictly skip OTP, 2FA, search, and CVV fields
        val excludedTokens = listOf("otp", "one-time", "2fa", "totp", "verification", "search", "query", "cvv", "coupon")
        if (excludedTokens.any { combinedMeta.contains(it) }) {
            return
        }

        val inputType = node.inputType
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        val isInputPassword = variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
            variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
            variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
            variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD

        val isHintPassword = hints.any { it.contains("password") } ||
            htmlAttrs.contains("type=password") ||
            idEntry.contains("password") ||
            idEntry.endsWith("pass") ||
            hintText.contains("password")

        val textVal = node.autofillValue?.let {
            if (it.isText) it.textValue?.toString().orEmpty() else ""
        } ?: node.text?.toString().orEmpty()

        if (isInputPassword || isHintPassword) {
            if (out.passwordId == null || textVal.isNotEmpty()) {
                out.passwordId = autofillId
            }
            if (textVal.isNotEmpty()) {
                out.passwordValue = textVal
            }
            return
        }

        val isInputEmail = variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
            variation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS
        val isExplicitUserHint = hints.any {
            it == View.AUTOFILL_HINT_USERNAME ||
                it == View.AUTOFILL_HINT_EMAIL_ADDRESS ||
                it == View.AUTOFILL_HINT_PHONE ||
                it.contains("username") ||
                it.contains("email")
        } || htmlAttrs.contains("type=email")

        val isHeuristicUser = isInputEmail ||
            isExplicitUserHint ||
            listOf("email", "user", "login", "account", "phone", "mobile").any {
                idEntry.contains(it) || hintText.contains(it)
            }

        if (isHeuristicUser) {
            if (out.usernameId == null) {
                out.usernameId = autofillId
            }
            if (isExplicitUserHint || isInputEmail) {
                out.isExplicitLoginUsername = true
            }
            if (textVal.isNotEmpty()) {
                out.usernameValue = textVal
            }
        }
    }
}

