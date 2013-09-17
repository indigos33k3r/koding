class PaymentController extends KDController

  getGroup = ->
    KD.getSingleton('groupsController').getCurrentGroup()

  getBalance: (type, callback)->
    if type is 'user'
      KD.remote.api.JRecurlyPlan.getUserBalance callback
    else
      KD.remote.api.JRecurlyPlan.getGroupBalance callback

  updateCreditCard: (type, callback=->)->
    @updateCreditCardModal {}, (newData)=>
      @modal.buttons.Save.hideLoader()
      if type is ['group', 'expensed']
        getGroup().setBillingInfo newData, callback
      else
        KD.remote.api.JRecurlyPlan.setUserAccount newData, callback

  updateBillingInfo: (type, callback=->)->
    @updateBillingInfoModal {}, (newData)=>
      log 'updateBillingInfo', newData
      @modal.buttons.Save.hideLoader()
      if type is ['group', 'expensed']
        getGroup().setBillingInfo newData, callback
      else
        KD.remote.api.JRecurlyPlan.setUserAccount newData, callback

  getBillingInfo: (type, callback)->
    if type is ['group', 'expensed']
      getGroup().getBillingInfo callback
    else
      KD.remote.api.JRecurlyPlan.getUserAccount callback

  getSubscription: do->
    findActiveSubscription = (subs, planCode, callback)->
      subs.reverse().forEach (sub)->
        if sub.planCode is planCode and sub.status in ['canceled', 'active']
          return callback sub

      callback 'none'

    (type, planCode, callback)->
      if type is 'group'
        getGroup().checkPayment (err, subs)=>
          findActiveSubscription subs, planCode, callback
      else
        KD.remote.api.JRecurlySubscription.getUserSubscriptions (err, subs)->
          findActiveSubscription subs, planCode, callback

  confirmPayment:(type, plan, callback=->)->
    getGroup().canCreateVM
      type     : type
      planCode : plan.code
    , (err, status)=>
      @getSubscription type, plan.code, (subscription)=>
        cb = (needBilling, balance, amount)=>
          @createPaymentConfirmationModal {
            needBilling, balance, amount, type, group, plan, subscription
          }, callback

        if status
          cb no, 0, 0
        else
          @getBillingInfo type, group, (err, account)=>
            needBilling = err or not account or not account.cardNumber

            @getBalance type, group, (err, balance)=>
              balance = 0  if err
              cb needBilling, balance, plan.feeMonthly

  makePayment: (type, plan, amount)->
    vmController = KD.getSingleton('vmController')

    if amount is 0
      vmController.createGroupVM type, plan.code
    else
      if type in ['group', 'expensed']
        getGroup().makePayment
          plan     : plan.code
          multiple : yes
        , (err, result)->
          return KD.showError err  if err
          vmController.createGroupVM type, plan.code
      else
        plan.subscribe multiple: yes, (err, result)->
          return KD.showError err  if err
          vmController.createGroupVM type, plan.code

  deleteVM: (vmInfo, callback)->
    type  =
      if vmInfo.planOwner.indexOf('user_') > -1 then 'user'
      else if vmInfo.type is 'expensed'         then 'expensed'
      else                                           'group'

    @getSubscription @getGroup(), type, vmInfo.planCode,\
      @createDeleteConfirmationModal.bind this, type, callback

  # views

  updateCreditCardModal:(data, callback) ->
    @modal = new PaymentForm {callback}

    form = @modal.modalTabs.forms['Billing Info']
    form.inputs[k]?.setValue v  for k, v of data

    @modal.on 'KDObjectWillBeDestroyed', => delete @modal
    return @modal

  updateBillingInfoModal:(data, callback)->
    @loadCountryData (err, countries, countryOfIp)=>
      @modal = new BillingForm {callback, countries, countryOfIp}

  loadCountryData:(callback)->
    return callback null, @countries, @countryOfIp  if @countries or @countryOfIp
    ip = $.cookie('clientIPAddress')
    KD.remote.api.JRecurly.getCountryData ip, (err, @countries, @countryOfIp)=>
      callback err, @countries, @countryOfIp

  createPaymentConfirmationModal: (options, callback)->
    options.callback or= callback
    return new PaymentConfirmationModal options

  createDeleteConfirmationModal: (type, callback, subscription)->
    return new PaymentDeleteConfirmationModal {subscription, type, callback}
