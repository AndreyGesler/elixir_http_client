defmodule HttpClient do
  ##############################################################################
  ##############################################################################
  @moduledoc """
  ## Module
  """

  # use Tesla
  # adapter(Tesla.Adapter.Finch, name: CommonFinch)

  use GenServer
  use Utils

  alias Tesla.Multipart, as: Multipart
  alias HttpClient.Services.HttpClientService, as: HttpClientService

  @auth_type_ids [:basic_auth, :telegram_bot_token, :bearer_token, :url_token]
  @http_methods [:post, :get]
  @exclude_headers_from_error ["authorization", "token", "secret"]

  ##############################################################################
  @doc """
  ### Ping pong.

  ### Examples

      iex> HttpClient.ping()
      :pong

  """
  def ping do
    :pong
  end

  ##############################################################################
  @doc """
  ### Function
  """
  def http_send!(method, url, body \\ nil, request_headers \\ [])

  def http_send!(method, url, body, request_headers)
      when is_nil(method) or is_nil(url) or is_nil(request_headers) or
             method not in @http_methods or not is_bitstring(url) or
             (not is_nil(body) and not is_bitstring(body) and not is_tuple(body)) or not is_list(request_headers) do
    UniError.raise_error!(:CODE_WRONG_FUNCTION_ARGUMENT_ERROR, [
      "method, url, request_headers can not be nil; url, if body not nil must be a string or tuple {:stream, stream}; request_headers must be a list; method, method must be one of #{inspect(@http_methods)}"
    ])
  end

  def http_send!(method, url, body, request_headers) do
    content_type = "application/json"
    request_headers = request_headers ++ [{"User-Agent", "PostmanRuntime/7.29.2"}]
    request_headers = request_headers ++ [{"Content-Type", content_type}]

    request_options = [
      # FIXME: Move it to config, please
      {:pool_timeout, 20_000},
      {:receive_timeout, 20_000}
    ]

    response =
      Finch.build(method, url, request_headers, body)
      |> Finch.request(CommonFinch, request_options)

    request_headers =
      Enum.reduce(
        request_headers,
        [],
        fn {name, value} = header, accum ->
          if String.downcase(name) in @exclude_headers_from_error do
            accum
          else
            accum ++ [header]
          end
        end
      )

    response_body =
      case response do
        {:ok, %Finch.Response{status: status} = response} ->
          if 200 <= status and status <= 299 do
            response.body
          else
            UniError.raise_error!(
              :CODE_HTTP_REMOTE_SERVICE_RESPONDED_NOT_2XX_ERROR,
              ["Remote service responded with error"],
              url: url,
              method: method,
              content_type: content_type,
              request_headers: request_headers,
              request_options: request_options,
              request_body: body,
              http_code: response.status,
              response_headers: response.headers,
              response_body: response.body
            )
          end

        {:ok, response} ->
          UniError.raise_error!(
            :CODE_HTTP_REMOTE_SERVICE_RESPONDED_WITH_ERROR,
            ["Remote service responded with error"],
            url: url,
            method: method,
            content_type: content_type,
            request_headers: request_headers,
            request_options: request_options,
            request_body: body,
            http_code: response.status,
            response_headers: response.headers,
            response_body: response.body
          )

        {:error, reason} ->
          # TODO: In this case re-query message or retry re-resend
          UniError.raise_error!(
            :CODE_HTTP_CONNECTION_ERROR,
            ["HTTP connection error"],
            url: url,
            method: method,
            content_type: content_type,
            request_headers: request_headers,
            request_options: request_options,
            request_body: body,
            previous: reason
          )

        unexpected ->
          UniError.raise_error!(
            :CODE_HTTP_CONNECTION_UNEXPECTED_ERROR,
            ["HTTP connection unexpected error"],
            url: url,
            method: method,
            content_type: content_type,
            request_headers: request_headers,
            request_options: request_options,
            previous: unexpected
          )
      end

    {:ok, response_body}
  end

  ##############################################################################
  @doc """
  ### Function

  fields = [
    {field_name, value, headers},
    {"client_id", "339eb665-65e6-44fe-85f4-01eccd2ec775", []}, 
    {"client_secret", "a15d9104-e632-4936-9c39-5c4b00c98653", []}, 
    {"grant_type", "client_credentials", []}
  ]
  """
  def build_multipart_form!(fields, content_type_param \\ "charset=utf-8", files \\ [], files_content \\ [])

  def build_multipart_form!(fields, content_type_param, files, files_content)
      when not is_list(fields) or not is_bitstring(content_type_param) or not is_list(files) or not is_list(files_content),
      do: UniError.raise_error!(:CODE_WRONG_FUNCTION_ARGUMENT_ERROR, ["fields, content_type_param, files, files_content cannot be nil; fields, files, files_content must be a list; content_type_param must be a string"])

  def build_multipart_form!(fields, content_type_param, files, files_content) do
    mp =
      Multipart.new()
      |> Multipart.add_content_type_param(content_type_param)

    mp =
      Enum.reduce(
        fields,
        mp,
        fn {field_name, value, headers}, accum ->
          accum
          |> Multipart.add_field(field_name, value, headers: headers)
        end
      )

    mp =
      Enum.reduce(
        files,
        mp,
        fn {file_path, name}, accum ->
          accum
          |> Multipart.add_file(file_path, name: name)
        end
      )

    mp =
      Enum.reduce(
        files_content,
        mp,
        fn {file_content, name}, accum ->
          accum
          |> Multipart.add_file(file_content, name)
        end
      )

    {:ok, mp}
  end

  ##############################################################################
  @doc """
  ### Function
  """
  def send_multipart_form!(url, fields \\ [], content_type_param \\ "charset=utf-8", files \\ [], files_content \\ [])

  def send_multipart_form!(url, fields, content_type_param, files, files_content)
      when not is_bitstring(url) or not is_bitstring(content_type_param) or not is_list(fields) or not is_list(files) or not is_list(files_content),
      do: UniError.raise_error!(:CODE_WRONG_FUNCTION_ARGUMENT_ERROR, ["url, fields, content_type_param, files, files_content cannot be nil; url, content_type_param must be a string; fields, files, files_content must be a list"])

  def send_multipart_form!(url, fields, content_type_param, files, files_content) do
    {:ok, mp} = build_multipart_form!(fields, content_type_param, files, files_content)
    mp_headers = Multipart.headers(mp)
    stream = Multipart.body(mp)

    http_send!(:post, url, {:stream, stream}, mp_headers)
  end

  ##############################################################################
  @doc """
  ### Function
  """
  def post!(url, body, request_headers \\ [])

  def post!(url, body, request_headers) do
    http_send!(:post, url, body, request_headers)
  end

  ##############################################################################
  @doc """
  ### Function

  :telegram_bot_token endpoint = https://example.com?<TOKEN> --->>> https://example.com?botSERGSDVSDGADFGZXVSDG
  """
  def get!(url, request_headers \\ [])

  def get!(url, request_headers) do
    http_send!(:get, url, nil, request_headers)
  end

  def build_auth!(auth_type_id, credential, endpoint)
      when auth_type_id not in @auth_type_ids or not is_map(credential) or (not is_nil(endpoint) and not is_bitstring(endpoint)),
      do:
        UniError.raise_error!(
          :CODE_WRONG_FUNCTION_ARGUMENT_ERROR,
          ["auth_type_id, credential cannot be nil; auth_type_id must be one of #{inspect(@auth_type_ids)}; endpoint if not nil must be a string"]
        )

  def build_auth!(:telegram_bot_token, %{token: token} = _credential, endpoint)
      when not is_bitstring(token) or not is_bitstring(endpoint),
      do: UniError.raise_error!(:CODE_WRONG_FUNCTION_ARGUMENT_ERROR, ["token, endpoint cannot be nil; token, endpoint must be a string"], auth_type_id: :telegram_bot_token)

  def build_auth!(:telegram_bot_token, %{token: token} = _credential, endpoint) do
    raise_if_empty!(endpoint, :string, "Wrong endpoint value")
    raise_if_empty!(token, :string, "Wrong token value")

    regex = ~r/<TOKEN>/
    endpoint = Regex.replace(regex, endpoint, "bot" <> token)

    {:ok, endpoint}
  end

  def build_auth!(:basic_auth, %{login: login, password: password} = _credential, _endpoint)
      when not is_bitstring(login) or not is_bitstring(password),
      do: UniError.raise_error!(:CODE_WRONG_FUNCTION_ARGUMENT_ERROR, ["login, password cannot be nil; login, password must be a string"], auth_type_id: :basic_auth)

  def build_auth!(:basic_auth, %{login: login, password: password} = _credential, _endpoint) do
    raise_if_empty!(login, :string, "Wrong login value")
    raise_if_empty!(password, :string, "Wrong password value")

    header = login <> ":" <> password
    {:ok, header} = Utils.encode64!(header)
    header = "Basic " <> header
    header = {"Authorization", header}

    {:ok, header}
  end

  def build_auth!(:bearer_token, %{token: token} = _credential, _endpoint)
      when not is_bitstring(token),
      do: UniError.raise_error!(:CODE_WRONG_FUNCTION_ARGUMENT_ERROR, ["token cannot be nil; token must be a string"], auth_type_id: :bearer_token)

  def build_auth!(:bearer_token, %{token: token} = _credential, _endpoint) do
    raise_if_empty!(token, :string, "Wrong token value")

    # {:ok, token} = Utils.encode64!(token)
    header = "Bearer " <> token
    header = {"Authorization", header}

    {:ok, header}
  end

  def build_auth!(auth_type_id, _credential, _endpoint),
    do: UniError.raise_error!(:CODE_WRONG_ARGUMENT_COMBINATION_ERROR, ["Wrong argument combination"], auth_type_id: auth_type_id)

  ##############################################################################
  @doc """
  Supervisor's child specification
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  ##############################################################################
  @doc """
  ## Function
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  ##############################################################################
  @doc """
  ## Function
  """
  @impl true
  def init(state) do
    UniError.rescue_error!(Utils.ensure_all_started!([:inets, :ssl]))

    Logger.info("[#{inspect(__MODULE__)}][#{inspect(__ENV__.function)}] I completed init part")
    {:ok, state}
  end

  ##############################################################################
  @doc """
  ## Function
  """
  @impl true
  def handle_info({:nodeup, node}, state) do
    UniError.rescue_error!(
      (
        Logger.info("[#{inspect(__MODULE__)}][#{inspect(__ENV__.function)}] Node #{inspect(node)} connected")

        {:ok, remote_postgresiar_node_name_prefixes} = Utils.get_app_env!(:postgresiar, :remote_node_name_prefixes)
        {:ok, nodes} = Utils.get_nodes_list_by_prefixes!(remote_postgresiar_node_name_prefixes, [node])

        if nodes == [] do
          Logger.warn("[#{inspect(__MODULE__)}][#{inspect(__ENV__.function)}] No postgresiar nodes in cluster, cannot start http clients")
        else
          {:ok, pid} = HttpClientService.start_transports!()
        end
      )
    )

    {:noreply, state}
  end

  ##############################################################################
  ##############################################################################
end
