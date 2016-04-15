$(document).on( "templateinit", (event) ->

  class MaxCulThermostatItem extends pimatic.DeviceItem

    constructor: (templData, @device) ->
      super(templData, @device)
      # The value in the input
      @inputValue = ko.observable()

      # temperatureSetpoint changes -> update input + also update buttons if needed
      @stAttr = @getAttribute('temperatureSetpoint')
      @inputValue(@stAttr.value())

      attrValue = @stAttr.value()
      @stAttr.value.subscribe( (value) =>
        @inputValue(value)
        attrValue = value
      )

      # input changes -> call changeTemperature
      ko.computed( =>
        textValue = @inputValue()
        if textValue? and attrValue? and parseFloat(attrValue) isnt parseFloat(textValue)
          @changeTemperatureTo(parseFloat(textValue))
      ).extend({ rateLimit: { timeout: 1000, method: "notifyWhenChangesStop" } })

      @synced = @getAttribute('synced').value

    afterRender: (elements) ->
      super(elements)
      # find the buttons
      @autoButton = $(elements).find('[name=autoButton]')
      @manuButton = $(elements).find('[name=manuButton]')
      @boostButton = $(elements).find('[name=boostButton]')
      @ecoButton = $(elements).find('[name=ecoButton]')
      @comfyButton = $(elements).find('[name=comfyButton]')
      @offButton = $(elements).find('[name=offButton]')
      # @vacButton = $(elements).find('[name=vacButton]')
      @input = $(elements).find('.spinbox input')
      @valvePosition = $(elements).find('.valve-position-bar')
      @input.spinbox()

      @updateButtons()
      @updatePreTemperature()
      @updateValvePosition()

      @getAttribute('mode')?.value.subscribe( => @updateButtons() )
      @stAttr.value.subscribe( => @updatePreTemperature() )
      @getAttribute('valve')?.value.subscribe( => @updateValvePosition() )
      return

    # define the available actions for the template
    modeAuto: -> @changeModeTo "auto"
    modeManu: -> @changeModeTo "manu"
    modeBoost: -> @changeModeTo "boost"
    modeEco: -> @changeTemperatureTo "#{@device.config.ecoTemp}"
    modeComfy: -> @changeTemperatureTo "#{@device.config.comfyTemp}"
    modeOff: -> @changeTemperatureTo "4.5"
    modeVac: -> @changeTemperatureTo "#{@device.config.vacTemp}"
    setTemp: -> @changeTemperatureTo "#{@inputValue.value()}"

    updateButtons: ->
      modeAttr = @getAttribute('mode')?.value()
      switch modeAttr
        when 'auto'
          @manuButton.removeClass('ui-btn-active')
          @boostButton.removeClass('ui-btn-active')
          @autoButton.addClass('ui-btn-active')
        when 'manu'
          @manuButton.addClass('ui-btn-active')
          @boostButton.removeClass('ui-btn-active')
          @autoButton.removeClass('ui-btn-active')
        when 'boost'
          @manuButton.removeClass('ui-btn-active')
          @boostButton.addClass('ui-btn-active')
          @ecoButton.removeClass('ui-btn-active')
          @comfyButton.removeClass('ui-btn-active')
          @autoButton.removeClass('ui-btn-active')
      return

    updatePreTemperature: ->
      if parseFloat(@stAttr.value()) is parseFloat("#{@device.config.ecoTemp}")
        @boostButton.removeClass('ui-btn-active')
        @ecoButton.addClass('ui-btn-active')
        @comfyButton.removeClass('ui-btn-active')
        @offButton.removeClass('ui-btn-active')
      else if parseFloat(@stAttr.value()) is parseFloat("#{@device.config.comfyTemp}")
        @boostButton.removeClass('ui-btn-active')
        @ecoButton.removeClass('ui-btn-active')
        @comfyButton.addClass('ui-btn-active')
        @offButton.removeClass('ui-btn-active')
      else if parseFloat(@stAttr.value()) is 4.5
        @boostButton.removeClass('ui-btn-active')
        @ecoButton.removeClass('ui-btn-active')
        @comfyButton.removeClass('ui-btn-active')
        @offButton.addClass('ui-btn-active')
      else
        @ecoButton.removeClass('ui-btn-active')
        @comfyButton.removeClass('ui-btn-active')
        @offButton.removeClass('ui-btn-active')
      return

    updateValvePosition: ->
      valveVal = @getAttribute('valve')?.value()
      if valveVal?
        @valvePosition.css('height', "#{valveVal}%")
        @valvePosition.parent().css('display', '')
      else
        @valvePosition.parent().css('display', 'none')

    changeModeTo: (mode) ->
      @device.rest.changeModeTo({mode}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changeTemperatureTo: (temperatureSetpoint) ->
      @input.spinbox('disable')
      @device.rest.changeTemperatureTo({temperatureSetpoint}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
        .always( => @input.spinbox('enable') )
        # register the item-class

  pimatic.templateClasses['maxcul-heating-thermostat'] = MaxCulThermostatItem
)
