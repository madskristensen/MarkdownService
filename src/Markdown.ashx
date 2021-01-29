<%@ WebHandler Language="C#" Class="Markdown" %>

using System;
using System.Web;
using System.Net;
using System.Text.RegularExpressions;
using Markdig;

public class Markdown : IHttpHandler
{
    private static Regex _regex = new Regex("\\s(src|href)=(\"|')(?!https?://)(?<path>[^\"']+)\\2", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static MarkdownPipeline _pipeline = new MarkdownPipelineBuilder()
                                                       .UseDiagrams()
                                                       .UseAdvancedExtensions()
                                                       .UseYamlFrontMatter()
                                                       .Build();

    public void ProcessRequest(HttpContext context)
    {
        Uri url;
        if (!Uri.TryCreate(context.Request.QueryString["url"], UriKind.Absolute, out url))
            return;

        try
        {
            string content = DownloadFile(url, context);

            if (!context.Response.SuppressContent)
            {
                var result = Markdig.Markdown.ToHtml(content, _pipeline);

                result = MakeAbsolute(result, url);

                context.Response.Write(result);
            }

            SetHeaders(context);
        }
        catch (Exception)
        {
            context.Response.Write("The markdown url could not be resolved.");
            context.Response.Status = "404 Not Found";
        }
    }

    private static void SetHeaders(HttpContext context)
    {
        context.Response.ContentType = "text/html";

        if (!context.Request.IsLocal)
        {
            context.Response.Cache.SetValidUntilExpires(true);
            context.Response.Cache.SetCacheability(HttpCacheability.Public);
            context.Response.Cache.SetExpires(DateTime.Now.AddMinutes(10));
            context.Response.Cache.VaryByParams["url"] = true;
            context.Response.Cache.SetOmitVaryStar(true);
            context.Response.Cache.SetMaxAge(new TimeSpan(0, 10, 0));
        }
    }

    private static string MakeAbsolute(string result, Uri url)
    {
        foreach (Match match in _regex.Matches(result))
        {
            string relative = match.Groups["path"].Value;

            if (relative[0] != '#')
            {
                string absolute = GetAbsoluteRoot(url) + "/" + relative;
                result = result.Replace(relative, absolute);
            }
        }

        return result;
    }

    private static string GetAbsoluteRoot(Uri url)
    {
        int index = url.AbsoluteUri.LastIndexOf('/') + 1;

        return url.AbsoluteUri.Substring(0, index);
    }

    private static string DownloadFile(Uri url, HttpContext context)
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls11 | SecurityProtocolType.Tls12 | SecurityProtocolType.Ssl3;

        using (WebClient client = new WebClient())
        {
            client.Encoding = System.Text.Encoding.UTF8;
            string content = client.DownloadString(url);
            string etag = client.ResponseHeaders["ETag"];

            SetConditionalGetHeaders(etag, context);

            return content;
        }
    }

    public static void SetConditionalGetHeaders(string etag, HttpContext context)
    {
        string ifNoneMatch = context.Request.Headers["If-None-Match"];

        if (ifNoneMatch != null && ifNoneMatch.Contains(","))
        {
            ifNoneMatch = ifNoneMatch.Substring(0, ifNoneMatch.IndexOf(",", StringComparison.Ordinal));
        }

        context.Response.AppendHeader("Etag", etag);
        context.Response.Cache.VaryByHeaders["If-None-Match"] = true;

        if (etag == ifNoneMatch)
        {
            context.Response.ClearContent();
            context.Response.StatusCode = (int)HttpStatusCode.NotModified;
            context.Response.SuppressContent = true;
        }
    }

    public bool IsReusable
    {
        get { return false; }
    }

}