defmodule YscWeb.AdminHelp.Guides do
  @moduledoc false

  defmodule GettingStarted do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "getting-started"

    @impl true
    def title, do: "Getting started in Admin"

    @impl true
    def summary,
      do:
        "Log in, find your way around the dashboard and sidebar, and understand what your role can do."

    @impl true
    def category, do: :getting_started

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"I can't see Users, Money, or Bookings in my sidebar — is something broken?",
         "No. Those areas are restricted to full admins. Volunteers see the content tools (Posts, Events, Newsletters, Media) plus check-in and scanning. If you need something from a restricted area, ask a board member."},
        {"How do I get a volunteer or admin account?",
         "Roles are assigned by an existing admin from the user management page. Contact the board if your account doesn't have admin access yet."},
        {"Can I break something by clicking around?",
         "Mostly no. Content starts as a draft and nothing goes public until you explicitly publish or send it. The two actions to be careful with are publishing an event (it emails members) and sending a newsletter (it emails all subscribers)."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Redirected back to the dashboard when opening a page — that page is admin-only and your account is a volunteer.",
        "Admin floating button missing on the public site — log out and back in, or go to /admin directly.",
        "After login you land on an onboarding page — finish it once, or navigate to /admin directly."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Open Admin",
          body:
            "Log in with your YSC account, then click the round **Admin** floating button in the corner of any page, or go directly to **/admin**.\n\nBoth admins and volunteers land on the dashboard. What you see there depends on your role — volunteers get a focused view with shortcuts to the content tools, while full admins also see membership, revenue, and application stats.",
          image: "ghost:getting-started-login",
          cta: %{label: "Open dashboard", path: "/admin"}
        },
        %{
          title: "Read the dashboard",
          body:
            "The dashboard is your daily starting point. It shows **upcoming events** with quick links to edit, view the public page, or open check-in, plus draft counts for posts and newsletters so unfinished work doesn't get forgotten.\n\nVolunteers see a stats row with one-click links to **Events**, **News & Posts**, and **Newsletters**. There is also a recent-discussions feed showing new member comments on posts, which is worth a glance — replying to comments is a nice touch.",
          image: "ghost:getting-started-dashboard"
        },
        %{
          title: "Navigate with the sidebar",
          body:
            "The dark sidebar on the left is how you move between tools: **Posts** (news articles), **Events**, **Newsletters**, **Media** (the shared image library), and **Help** (these guides).\n\nFull admins also see Users, Memberships, Bookings, Money, and Settings. The sidebar can be collapsed with the chevron at the top to give content more room — your preference is remembered.",
          image: "ghost:getting-started-sidebar",
          hotspots: [
            %{
              area: :sidebar,
              x: 4,
              y: 12,
              w: 96,
              h: 72,
              label: "Admin sidebar"
            }
          ]
        },
        %{
          title: "Know your role",
          body:
            "**Volunteers** can do everything content-related: write and publish posts, create and publish events, compose and send newsletters, manage the media library, and run event check-in and QR scanning on the day.\n\n**Full admins** additionally manage members and applications, cabin bookings, refunds and finances, memberships, and site settings.\n\nIf a page redirects you back to the dashboard, it's admin-only — that's by design, not a bug.",
          cta: %{
            label: "Read the full roles guide",
            path: "/admin/help/getting-started/roles"
          }
        },
        %{
          title: "Where to get help",
          body:
            "Every major admin screen has a small **?** help link near the title that opens the matching guide.\n\nEach guide also has a **Print / Save PDF** button so you can save a copy or email it to a new volunteer. If something looks wrong or you're unsure about an action that emails members, ask a board member before clicking — better a question than a mass email."
        }
      ]
    end
  end

  defmodule RolesAndPermissions do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "getting-started/roles"

    @impl true
    def title, do: "Volunteer vs admin permissions"

    @impl true
    def summary,
      do:
        "What volunteers can do in Admin, what is restricted to full admins, and how the sidebar differs by role."

    @impl true
    def category, do: :getting_started

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"I'm a volunteer — can I publish posts and send newsletters?",
         "Yes. Content tools (posts, events, newsletters, media library browsing, check-in, and QR scanning) are all in scope for volunteers."},
        {"Why was I redirected when I opened Users or Money?",
         "Those areas are full-admin only. Volunteers are redirected back to the dashboard by design — ask a board member if you need something from a restricted page."},
        {"Can volunteers upload images to the media library?",
         "Browsing works; creating or editing library images is reserved for full admins today. Use images already in the library, or ask an admin to upload one for you."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Missing sidebar items (Users, Bookings, Money) — you are a volunteer; those links are hidden on purpose.",
        "Need a refund or member record changed — full-admin task; contact the board.",
        "Want admin access — an existing admin assigns roles from the Users page."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Two staff roles",
          body:
            "Everyone with admin access is either a **volunteer** or a **full admin**. Both sign in the same way and land on `/admin`, but the dashboard and sidebar show different tools.\n\nVolunteers focus on **content and day-of operations**. Full admins additionally run membership, bookings, money, and site settings.",
          image: "ghost:getting-started-dashboard"
        },
        %{
          title: "What volunteers can do",
          body:
            "**Posts** — write, edit, and publish news articles.\n\n**Events** — create, edit, publish, sell tickets, and email attendees.\n\n**Newsletters** — compose, test, send, schedule, and manage subscribers.\n\n**Media** — browse the shared image library (uploads are admin-only).\n\n**Day-of** — event check-in, QR scanner sessions, and membership check-in desks.\n\n**Help** — these step-by-step guides, including print/PDF.",
          image: "ghost:getting-started-sidebar",
          hotspots: [
            %{
              area: :sidebar,
              x: 4,
              y: 18,
              w: 96,
              h: 55,
              label: "Volunteer sidebar"
            }
          ]
        },
        %{
          title: "What only full admins can do",
          body:
            "If you open one of these as a volunteer, you will be **redirected back to the dashboard** — that is expected, not a bug:\n\n**Users** (applications and roles), **Bookings** (cabins), **Money** (payments and refunds), **Settings**, and internal tools like impersonation.\n\n**Memberships** and **Money** also depend on board position — the membership director and treasurer see those extra nav items when they are full admins.",
          cta: %{label: "Back to dashboard", path: "/admin"}
        },
        %{
          title: "When to ask for help",
          body:
            "If you need a refund issued, a member looked up, a role changed, or a setting updated, loop in a **board member / full admin**.\n\nFor content questions — how to publish, send a newsletter, or run check-in — use the **?** links on each admin page or browse all guides from **Help** in the sidebar.",
          cta: %{label: "Browse help guides", path: "/admin/help"}
        }
      ]
    end
  end

  defmodule PublishPost do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "posts/publish"

    @impl true
    def title, do: "Publish a news article"

    @impl true
    def summary,
      do:
        "Write a post in the rich-text editor, set the URL and featured image, preview on every device, and publish to Club News."

    @impl true
    def category, do: :posts

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"Why can't I publish without a featured image?",
         "The featured image is what shows on the /news listing, in link previews, and in newsletters that include the post. Publishing without one would leave an empty card. If you click Publish without an image, the settings modal opens — pick an image and the publish completes automatically."},
        {"Does my post save automatically?",
         "Yes. A couple of seconds after you stop typing, the draft saves — you'll see a brief \"Saving...\" indicator near the title. The very first auto-save creates the post and the URL changes from /admin/posts/new to /admin/posts/<id>."},
        {"Can I edit a post after publishing?",
         "Yes. Open it from the Posts list and edit as usual; changes auto-save and go live immediately. Be careful changing the URL slug after publishing — links already shared will break."},
        {"Can members see my draft?",
         "No. Drafts are only visible to admins and volunteers. If you open the public link of a draft, you'll see an amber \"Staff preview\" banner that regular members never see."},
        {"Can members comment on posts?",
         "Yes, logged-in members can comment on published articles. New comments show up in the Recent discussions feed on the admin dashboard."},
        {"Can I schedule a post for later?",
         "Not currently — publishing is immediate. Keep the post as a draft until the day you want it live. (Events and newsletters do support scheduling.)"}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Publish opened a settings modal instead of publishing — that means no featured image is set; pick one and publishing finishes on its own.",
        "URL slug stopped following the title — once you manually edit the slug, it no longer auto-syncs. That's intentional.",
        "Preview shows an amber staff banner — normal for drafts; it disappears once published.",
        "Accidentally deleted a post — deletion is soft. Open the post from the editor and use Restore, or ask an admin.",
        "Pasted text looks messy — paste as plain text (Cmd/Ctrl+Shift+V) and re-apply formatting with the toolbar."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Create a new post",
          body:
            "Go to **Posts** in the sidebar and click **New Post**. The editor opens with the placeholder title \"New Untitled Post\".\n\nNothing is saved until you start typing — the first auto-save creates the draft and the page URL updates to the post's permanent address. From then on, every change auto-saves.",
          image: "ghost:posts-list",
          hotspots: [%{x: 78, y: 6, w: 18, h: 8, label: "New Post"}],
          cta: %{label: "Open Posts", path: "/admin/posts"}
        },
        %{
          title: "Set the title and URL",
          body:
            "Click the title to edit it. The public URL slug (e.g. /posts/midsummer-recap-2026) is generated from the title automatically and keeps following it until you edit the slug by hand.\n\nKeep titles short and specific — they appear on /news cards, in the newsletter, and in browser tabs. \"Midsummer 2026 — photos and thanks\" beats \"Update\".",
          image: "ghost:posts-editor",
          hotspots: [
            %{
              expanded: %{x: 27, y: 4, w: 46, h: 7},
              collapsed: %{x: 26, y: 4, w: 44, h: 7},
              label: "Post title"
            },
            %{
              expanded: %{x: 40, y: 13, w: 24, h: 5},
              collapsed: %{x: 36, y: 12, w: 22, h: 6},
              label: "URL slug"
            }
          ]
        },
        %{
          title: "Write the body",
          body:
            "Write in the rich-text editor below the title. The toolbar gives you **bold**, *italic*, headings, quotes, links, and bulleted or numbered lists.\n\nTo add photos inside the article, use the image button in the toolbar — it opens the shared media library, so upload your photos there first (or drop them straight into the picker). Images are resized and optimized automatically.\n\nA good club article: a short opening paragraph saying what happened or what's coming, a few photos, and clear details (dates, places, names) members might search for later.",
          image: "ghost:posts-editor",
          image_scroll: "ghost-post-editor-body",
          hotspots: [
            %{
              expanded: %{x: 30, y: 32, w: 60, h: 70},
              collapsed: %{x: 30, y: 26, w: 60, h: 70},
              label: "Rich-text editor"
            }
          ]
        },
        %{
          title: "Add the featured image",
          body:
            "Open the **⋮** menu in the top-right of the editor and choose **Post Settings**, then pick a **Featured Image** from the media library.\n\nThis image is the post's \"face\" — it shows on the /news listing, on the featured hero if the post gets pinned, and in newsletters. Choose a landscape photo that still reads well when cropped small. This step is required: the Publish button won't complete without it.",
          image: "ghost:posts-settings",
          public_image: "ghost:public-news-article"
        },
        %{
          title: "Preview before publishing",
          body:
            "Click **Preview** to open a full-screen preview with **phone**, **tablet**, and **desktop** mockups — most members read on their phones, so always check the phone view.\n\nYou can also open the public URL directly while the post is still a draft: staff see the real page with an amber \"Staff preview\" banner. That link is safe to share with another volunteer or board member for review — regular members can't open it.",
          image: "ghost:posts-publish"
        },
        %{
          title: "Publish",
          body:
            "Click **Publish**. The post goes live immediately at /news and its own URL, appears in the site's news feed, and members can comment on it.\n\nYour name appears as the byline, along with your board position if you hold one at publish time. After publishing you can still edit (changes are live immediately), **pin** the post to feature it at the top of /news, or share its URL in the next newsletter.",
          image: "ghost:posts-publish",
          hotspots: [
            %{
              expanded: %{x: 88, y: 2, w: 7, h: 8},
              collapsed: %{x: 90, y: 2, w: 7, h: 8},
              label: "Publish"
            }
          ],
          public_image: "ghost:public-news-list",
          cta: %{label: "Start a new post", path: "/admin/posts/new"}
        }
      ]
    end
  end

  defmodule PinAndDrafts do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "posts/pin-and-drafts"

    @impl true
    def title, do: "Pin posts and manage drafts"

    @impl true
    def summary,
      do:
        "Feature an article at the top of Club News, find old posts with filters, and clean up or restore drafts."

    @impl true
    def category, do: :posts

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"What does pinning actually do?",
         "The pinned post becomes the large featured article at the top of /news. There can only be one pinned post — pinning a new one automatically unpins the previous."},
        {"Can I pin a draft?",
         "No — only published posts can be pinned, since the pin controls what shows publicly on /news."},
        {"Is deleting permanent?",
         "No. Deletes are soft: the post is hidden but kept in the database. It can be restored to a draft from the editor's menu (restoring clears the publish date and any pin)."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Pinned the wrong post — just pin the right one; the old pin clears automatically.",
        "Can't find an old article — clear the state filter; it may be filtered to Drafts only. Also try the author and date filters.",
        "Delete option missing on a published post in the list — the list only deletes drafts; published posts are deleted from inside the editor's ⋮ menu."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Pin a featured post",
          body:
            "On the Posts list, open the **⋮** menu on any **published** post and choose **Pin post**. It becomes the large hero article at the top of /news.\n\nOnly one post is pinned at a time — pinning a new one silently unpins the previous, so you never need to unpin first. Use the pin for the most timely or important article: an upcoming AGM, Midsummer recap, or a big announcement.",
          image: "ghost:posts-list",
          hotspots: [
            %{
              expanded: %{x: 79, y: 32, w: 15, h: 24},
              collapsed: %{x: 82, y: 32, w: 14, h: 24},
              label: "⋮ actions menu with pin option",
              style: :hint
            }
          ],
          public_image: "ghost:public-news-pinned",
          cta: %{label: "Open Posts", path: "/admin/posts"}
        },
        %{
          title: "Search and filter the list",
          body:
            "Use the search box to find posts by title. The filter dropdown narrows by **state** (Published / Draft), **author**, and **date posted** range.\n\nA practical habit: filter to Drafts once in a while to spot stale half-written articles — either finish them or delete them so the list stays useful. The comment count column also shows which articles are generating discussion."
        },
        %{
          title: "Delete drafts you no longer need",
          body:
            "From the list's **⋮** menu, drafts can be deleted after a confirmation. Deletion is **soft** — the post is hidden, not destroyed.\n\nPublished posts can't be deleted from the list; open the post in the editor and use **Delete Post** in its ⋮ menu instead. That extra step is deliberate, since deleting a published article removes it from the public site."
        },
        %{
          title: "Restore a deleted post",
          body:
            "Open a deleted post in the editor and click **Restore**. It comes back as a **draft** — the publish date and any pin are cleared, so you'll need to publish (and optionally pin) it again.\n\nIf you can't find a deleted post, ask an admin to help locate it."
        }
      ]
    end
  end

  defmodule ComposeNewsletter do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "newsletters/compose"

    @impl true
    def title, do: "Compose a newsletter"

    @impl true
    def summary,
      do:
        "Build an email edition with a cover photo, subject line, intro, and curated posts and events — with a live preview as you go."

    @impl true
    def category, do: :newsletters

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"Do I need to press save?",
         "No. Editions auto-save a couple of seconds after you stop editing. The first save creates the edition and the URL changes from /new to /admin/newsletters/<id>/edit — after that your work is safe even if you close the tab."},
        {"What's the difference between the headline and the subject?",
         "The subject is what appears in the recipient's inbox; the headline is the large title inside the email. They can differ — e.g. subject \"Midsummer tickets are live 🎉\", headline \"June at YSC\"."},
        {"Why does the subject show a warning?",
         "Subjects over ~60 characters get cut off in many email clients, so the editor warns you. Shorter is almost always better."},
        {"Can I write a fully custom email?",
         "Newsletters are structured: cover + intro + selected posts and events. For long-form content, publish it as a post first, then include that post in the edition. This keeps every edition consistent and mobile-friendly."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "A post or event is missing from the picker — pickers show the 50 most recent posts and 50 upcoming events; the item may be a draft (publish it first) or too old.",
        "Selected items appear in the wrong order — order follows the sequence you clicked them in; deselect and reselect to reorder.",
        "Preview not updating — give it a moment after typing; the preview re-renders after the auto-save debounce.",
        "Edition opened read-only — it has already been sent; sent editions are locked. Create a new edition instead."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Start a new edition",
          body:
            "Go to **Newsletters** in the sidebar and click **New Newsletter**.\n\nOn desktop the screen splits in two: the editor on the left and a **live preview of the actual email** on the right. On a phone or narrow window, switch between Editor and Preview tabs at the top. Everything auto-saves — the first save creates the edition and pins down its URL.",
          image: "ghost:newsletter-compose",
          hotspots: [
            %{
              expanded: %{x: 26, y: 8, w: 35, h: 92},
              collapsed: %{x: 26, y: 8, w: 35, h: 92},
              label: "Editor (left)",
              style: :hint
            },
            %{
              expanded: %{x: 62, y: 8, w: 35, h: 92},
              collapsed: %{x: 62, y: 8, w: 35, h: 92},
              label: "Email preview (right)",
              style: :hint
            }
          ],
          cta: %{label: "New newsletter", path: "/admin/newsletters/new"}
        },
        %{
          title: "Pick a cover photo",
          body:
            "Choose a **cover photo** from the media library — it sits at the top of the email and sets the tone. A bright landscape photo from a recent club event works well.\n\nIf the photo you want isn't in the library yet, upload it via **Media** first (or directly in the picker)."
        },
        %{
          title: "Write the headline and subject",
          body:
            "The **headline** is the big title inside the email; the **subject** is the inbox line. The editor warns when the subject passes ~60 characters because longer subjects get truncated on phones.\n\nGood subjects are specific and front-loaded: \"Midsummer tickets now on sale\" rather than \"YSC Newsletter — June 2026 edition with updates\".",
          image: "ghost:newsletter-compose"
        },
        %{
          title: "Write the intro",
          body:
            "The intro is the opening section — a few warm sentences from the club to the members. Use the toolbar for bold, links, and lists, and the image button to drop in a photo from the library.\n\nKeep it short: two or three short paragraphs. The detailed content lives in the posts and events you attach next.",
          image: "ghost:newsletter-compose"
        },
        %{
          title: "Select posts and events",
          body:
            "Below the intro are two pickers: **Latest news** (the 50 most recent published posts) and **Upcoming events**. Click a card to include it; click again to remove it.\n\n**The order you click is the order in the email**, so click your lead story first. Each included post or event becomes a styled card in the email linking back to the site — recipients click through, and those clicks are tracked in the stats.",
          image: "ghost:newsletter-compose",
          image_scroll: "ghost-newsletter-post-picker",
          hotspots: [
            %{x: 26, y: 28, w: 36, h: 80, label: "Post and event pickers"}
          ],
          public_image: "ghost:public-newsletter-edition"
        },
        %{
          title: "Check the preview",
          body:
            "The preview pane renders the **real email** exactly as subscribers will receive it, shown from a subscriber's perspective.\n\nScroll the whole thing top to bottom: cover, headline, intro, every card, footer. Check for typos in the subject especially — it's the one thing you can't fix after sending. When it looks right, continue to the send guide.",
          image: "ghost:newsletter-compose",
          image_scroll: "ghost-newsletter-preview-panel",
          cta: %{
            label: "Next: send or schedule",
            path: "/admin/help/newsletters/send"
          }
        }
      ]
    end
  end

  defmodule SendNewsletter do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "newsletters/send"

    @impl true
    def title, do: "Send or schedule a newsletter"

    @impl true
    def summary,
      do:
        "Test on your own inbox, send to all subscribers now, or schedule delivery — then read the engagement stats."

    @impl true
    def category, do: :newsletters

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"Who receives the newsletter?",
         "All active subscribers — members and non-members who signed up on the site, plus anyone added manually on the Subscribers tab. The current count shows at the top of the Newsletters page."},
        {"Can I unsend or edit after sending?",
         "No. Once sent, the edition is permanently read-only and the emails are out. This is why the test-send step matters."},
        {"Can I edit a scheduled edition?",
         "Yes — scheduled editions stay editable until the send time. You can keep polishing right up until delivery."},
        {"What timezone does scheduling use?",
         "The picker uses your local timezone and shows it explicitly. A backup job checks every few minutes, so scheduled sends go out within a few minutes of the chosen time."},
        {"Where do the stats come from?",
         "Delivery, opens, clicks, and bounces are reported back by the email provider and accumulate over the days after sending. A summary email also goes to the club inbox about 24 hours after each send."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Send test does nothing — the edition must be saved first; type anything to trigger the auto-save, then retry.",
        "Test email didn't arrive — check your spam folder; tests go to the email on your own admin account.",
        "Edition stuck in \"sending\" — large lists take a few minutes; the list page updates live when it finishes.",
        "Sent to subscribers but stats are empty — opens and clicks trickle in over hours and days; check back tomorrow."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Make sure the edition is saved",
          body:
            "Sending requires a saved edition — confirm the URL looks like /admin/newsletters/<id>/edit. If you're still on /new, make any small edit and the auto-save will create it.\n\nGive the preview one final read. After the next steps there is no undo.",
          cta: %{label: "Open newsletters", path: "/admin/newsletters"}
        },
        %{
          title: "Send a test to yourself",
          body:
            "In the **Email Preview** panel on the right, click **Send test** (top-right of the preview header). A real copy of the email goes to **your own address** — the one on your admin account.\n\nOpen it on your phone, not just your computer: most subscribers read on mobile. Check the subject, the cover image, every link, and how the post/event cards look. Fix anything in the editor and send another test; there's no limit.",
          image: "ghost:newsletter-compose",
          image_scroll: "ghost-newsletter-preview-panel",
          hotspots: [
            %{
              expanded: %{x: 84, y: 2, w: 11, h: 6},
              collapsed: %{x: 87, y: 2, w: 9, h: 6},
              label: "Send test"
            }
          ]
        },
        %{
          title: "Send now…",
          body:
            "**Send now** opens a confirmation dialog — this is the point of no return. On confirm, the edition is queued and emailed to **every active subscriber**, the status moves through *sending* to *sent*, and the edition becomes permanently read-only.\n\nThe newsletters list updates live when sending completes. The sent edition is also archived publicly on the site's newsletter archive.",
          image: "ghost:newsletter-compose",
          image_scroll: "ghost-newsletter-action-bar",
          hotspots: [
            %{
              expanded: %{x: 74, y: 90, w: 10, h: 7},
              collapsed: %{x: 78, y: 90, w: 10, h: 8},
              label: "Send now"
            }
          ],
          public_image: "ghost:public-newsletter-archive"
        },
        %{
          title: "…or schedule for later",
          body:
            "**Schedule** lets you pick a date and time in your local timezone — the edition shows as *Scheduled* and goes out automatically.\n\nScheduled editions remain **editable until they send**, so you can schedule Friday's newsletter on Tuesday and keep polishing. Weekday mornings tend to get the best open rates.",
          image: "ghost:newsletter-compose",
          image_scroll: "ghost-newsletter-action-bar",
          hotspots: [
            %{
              expanded: %{x: 83, y: 90, w: 12, h: 8},
              collapsed: %{x: 86, y: 90, w: 10, h: 8},
              label: "Schedule"
            }
          ]
        },
        %{
          title: "Read the stats",
          body:
            "Open a sent edition to see the results banner: emails sent, **unique opens**, **clicks**, and **bounces**, plus a **clicks-by-link** breakdown showing exactly which posts and events people tapped.\n\nUse this to learn what lands: if event cards always outperform long intros, lead with events next time. A stats summary email also arrives at the club inbox about a day after each send."
        }
      ]
    end
  end

  defmodule ManageSubscribers do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "newsletters/subscribers"

    @impl true
    def title, do: "Manage newsletter subscribers"

    @impl true
    def summary,
      do:
        "See who receives the newsletter, add people manually, and remove or re-add addresses."

    @impl true
    def category, do: :newsletters

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"How do people normally subscribe?",
         "Through the signup form on the public website. Manual adding is for special cases — someone asks at an event, a partner organisation, a board member's alternate address."},
        {"Do I need permission to add someone?",
         "Yes — only add people who have clearly asked to receive the newsletter. Adding addresses without consent harms the club's email reputation and can get our emails marked as spam."},
        {"What happens when someone unsubscribes?",
         "Every newsletter has an unsubscribe link. People who use it become inactive automatically and stop receiving editions — you don't need to do anything."},
        {"Why is an address shown as inactive?",
         "Either they unsubscribed or an admin removed them. Inactive subscribers don't receive newsletters but stay in the list so they can be re-added if they ask."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Added address rejected — the address may be invalid or from a disposable email domain, which the system blocks.",
        "Someone says they're not getting newsletters — search their email on the subscribers tab; if inactive, re-add them (with their consent) and ask them to check spam.",
        "Can't find a subscriber — switch the status filter to All; the default views can hide inactive entries."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Open the Subscribers tab",
          body:
            "Go to **Newsletters** and switch to the **Subscribers** tab. The list shows each subscriber's email, name (when known), status, how they signed up, and when.\n\nThe subscriber count at the top of the page is the audience size for your next send.",
          cta: %{
            label: "Open subscribers",
            path: "/admin/newsletters?tab=subscribers"
          }
        },
        %{
          title: "Search and filter",
          body:
            "Use the search box to find a specific email and the status filter to switch between **Active**, **Inactive**, and **All**.\n\nActive subscribers receive newsletters; inactive ones (unsubscribed or removed) don't, but stay listed so they can be brought back.",
          image: "ghost:newsletter-subscribers"
        },
        %{
          title: "Add a subscriber manually",
          body:
            "Click **Add subscriber**, enter the email address, and confirm. The entry is recorded as admin-added so we always know how someone got on the list.\n\nOnly add people who explicitly asked — for example someone who signed a paper list at an event. Invalid and disposable addresses are rejected automatically.",
          image: "ghost:newsletter-subscribers"
        },
        %{
          title: "Remove or re-add",
          body:
            "**Remove** unsubscribes an address immediately — use it when someone asks to stop receiving emails.\n\n**Re-add** reactivates an inactive subscriber — use it when someone unsubscribed by accident or changed their mind. Both take effect from the next send."
        }
      ]
    end
  end

  defmodule CreateEvent do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "events/create"

    @impl true
    def title, do: "Create an event"

    @impl true
    def summary,
      do:
        "Set up the details tab: cover image, title and summary, dates, location with map pin, full description, hosts, and agenda."

    @impl true
    def category, do: :events

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"What happens when I click New Event?",
         "A draft titled \"New Event\" is created immediately and you land in its editor. Drafts are invisible to members, so take your time."},
        {"Can I copy last year's event instead of starting fresh?",
         "Yes — find the old event in the list, open its ⋮ menu, and choose Copy. The copy is a new draft with the ticket tiers, agenda, and FAQs duplicated. Update the dates and details before publishing."},
        {"What is the Partiful link for?",
         "If the event is organised on Partiful instead of our own ticketing, paste its link on the Details tab. The public page then sends people to Partiful — and the Tickets tab is disabled, since registration happens externally. Choose one approach, not both."},
        {"Why is the summary limited to 200 characters?",
         "The summary is the teaser on event cards across the site and newsletter. The full description belongs in the Overview section, which has no limit."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Tickets tab is greyed out — a Partiful link is set on Details; remove it to use built-in ticketing.",
        "Publish button disabled — a title and start date are required before an event can be published.",
        "Host not found in search — hosts must have a member account; check the spelling of their name.",
        "Closed the tab mid-edit — no problem, the draft is saved; reopen it from the Drafts tab on the events list."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Start a draft",
          body:
            "On the **Events** list, click **New Event**. A draft is created instantly and you're taken to its editor.\n\nThe editor has three tabs: **Event Details** (this guide), **Tickets**, and **Updates**. Drafts are invisible to members until you publish, so nothing here is public yet.\n\nRunning a repeat of an earlier event? Use **Copy** on the old event instead — it duplicates tiers, agenda, and FAQs into a fresh draft.",
          image: "ghost:events-list",
          hotspots: [
            %{
              expanded: %{x: 84, y: 5, w: 11, h: 8},
              collapsed: %{x: 87, y: 5, w: 10, h: 8},
              label: "New Event"
            }
          ],
          cta: %{label: "Create new event", path: "/admin/events/new"}
        },
        %{
          title: "Cover image, title, and summary",
          body:
            "Pick a **cover image** from the media library — it headlines the public event page, the events listing, and newsletter cards.\n\nWrite a clear **title** and a **summary** of at most 200 characters. The summary is the teaser members see on cards, so make it sell the event: \"Sauna, swimming and BBQ at Clear Lake — members and guests welcome.\"\n\nIf the event is organised on **Partiful**, paste the link here instead of using the Tickets tab — the two are mutually exclusive.",
          image: "ghost:events-edit",
          image_scroll: "ghost-event-cover-section",
          hotspots: [
            %{
              expanded: %{x: 28, y: 89, w: 52, h: 11},
              collapsed: %{x: 26, y: 89, w: 52, h: 11},
              label: "Partiful link"
            },
            %{
              expanded: %{x: 28, y: 4, w: 44, h: 50},
              collapsed: %{x: 26, y: 4, w: 44, h: 50},
              label: "Cover image"
            },
            %{
              expanded: %{x: 28, y: 65, w: 52, h: 23},
              collapsed: %{x: 26, y: 65, w: 52, h: 23},
              label: "Basic details"
            }
          ],
          public_image: "ghost:public-event-page",
          public_hotspots: [
            %{x: 1, y: 2, w: 99, h: 84, label: "Hero card on the event page"}
          ]
        },
        %{
          title: "Dates, times, and location",
          body:
            "Set the **date** (single day or a range for multi-day events like cabin weekends), plus start and end times.\n\nEnter the **location** and drop the **map pin** so members get accurate directions — the pin powers the map on the public page. For venues with tricky entrances, add arrival notes in the Overview.",
          image: "ghost:events-edit",
          image_scroll: "ghost-event-date-section",
          hotspots: [
            %{x: 27, y: 4, w: 48, h: 18, label: "Date, time, and map"}
          ]
        },
        %{
          title: "Write the overview",
          body:
            "The **Overview** is the full description on the public page, written in the rich-text editor — headings, lists, links, and inline photos from the media library all work.\n\nCover what attendees actually ask: what's included, what to bring, parking and transit, guest policy, and food/drink arrangements. A thorough overview saves you from answering the same questions by email.",
          image: "ghost:events-edit",
          image_scroll: "ghost-event-overview-section",
          hotspots: [
            %{
              expanded: %{x: 28, y: 1, w: 60, h: 80},
              collapsed: %{x: 26, y: 1, w: 50, h: 80},
              label: "Overview editor"
            }
          ],
          public_image: "ghost:public-event-page",
          public_image_scroll: "ghost-public-event-details",
          public_hotspots: [
            %{
              x: 1,
              y: 62,
              w: 64,
              h: 22,
              label: "Details section"
            }
          ]
        },
        %{
          title: "Add hosts",
          body:
            "Search for members by name and add them as **hosts**. On the public event page, hosts appear at the top of the **Attendees** section at the bottom of the page — with an amber ring and a **Host** label under their name.\n\nAdd everyone who's actually organising — it's also a nice way to credit volunteers.",
          image: "ghost:events-edit",
          image_scroll: "ghost-event-hosts-section",
          hotspots: [
            %{
              expanded: %{x: 28, y: 53, w: 60, h: 10},
              collapsed: %{x: 27, y: 53, w: 49, h: 10},
              label: "Hosts search"
            }
          ],
          public_image: "ghost:public-event-page",
          public_image_scroll: "ghost-public-event-hosts",
          public_hotspots: [
            %{
              x: 1,
              y: 82,
              w: 44,
              h: 20,
              label: "Host in Attendees"
            }
          ]
        },
        %{
          title: "Build the agenda",
          body:
            "For events with a schedule, add **agenda** sections with timed items — e.g. \"17:00 Doors open\", \"18:00 Dinner\", \"20:00 Singing\". Items can be reordered or deleted as plans firm up.\n\nThe agenda renders as a clean timeline on the public page. Skip it for unstructured socials; use it for anything with a programme.\n\nNext: set up tickets and capacity.",
          image: "ghost:events-edit",
          image_scroll: "ghost-event-agenda-section",
          hotspots: [
            %{x: 26, y: 36, w: 40, h: 60, label: "Agenda cards and Add Agenda"}
          ],
          public_image: "ghost:public-event-agenda",
          public_image_scroll: "ghost-public-event-agenda",
          public_hotspots: [
            %{
              x: 6,
              y: 12,
              w: 88,
              h: 42,
              label: "Agenda timeline on the site",
              style: :hint
            }
          ],
          cta: %{
            label: "Next: tickets and capacity",
            path: "/admin/help/events/tickets"
          }
        }
      ]
    end
  end

  defmodule EventTickets do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "events/tickets"

    @impl true
    def title, do: "Event tickets and capacity"

    @impl true
    def summary,
      do:
        "Set overall capacity, create free, paid, or donation ticket tiers with sale windows, and reserve tickets for specific members."

    @impl true
    def category, do: :events

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"What ticket types exist?",
         "Free (RSVP only), Paid (fixed price, card payment at checkout), and Donation (attendee chooses the amount). One event can mix tiers — e.g. \"Member free\" + \"Guest $20\"."},
        {"What does \"requires registration\" mean on a tier?",
         "It collects attendee details for each ticket at checkout, so you know exactly who is coming — useful for capacity-limited or catered events."},
        {"What is Tickets TBD?",
         "A placeholder mode when you haven't decided pricing yet. The event can be published with \"tickets to be announced\" and you add real tiers later."},
        {"Can I delete a tier after sales started?",
         "Not once tickets are sold — that would orphan real purchases. You can edit the tier or stop its sales window instead."},
        {"How does overall capacity interact with tier quantities?",
         "Event capacity is the hard ceiling across all tiers; each tier can also have its own quantity. Sales stop when either limit is reached."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Whole Tickets tab disabled — a Partiful link is set on the Details tab; registration is external for this event.",
        "Members report they can't buy tickets — check the tier's sales window dates and whether the tier or event capacity has sold out.",
        "Need to hold seats for the board — use a reservation rather than buying tickets yourself; reservations can be cancelled to free the seats.",
        "Sold/reserved counts look off — counts include reservations, which hold capacity just like sales."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Open the Tickets tab",
          body:
            "From the event editor, switch to the **Tickets** tab.\n\nIf it's greyed out, the event has a Partiful link on the Details tab — built-in ticketing and Partiful are mutually exclusive. Remove the link if you want to sell tickets here.",
          image: "ghost:events-tickets",
          hotspots: [
            %{x: 26, y: 6, w: 44, h: 18, label: "Editor header and tabs"}
          ]
        },
        %{
          title: "Set event capacity",
          body:
            "Choose **unlimited** attendance or set a **maximum number of attendees** for the whole event.\n\nCapacity is the hard ceiling across all tiers combined. For venue-limited events (cabin dinners, boat trips), set this first so overselling is impossible no matter how tiers are configured.",
          image: "ghost:events-tickets",
          image_scroll: "ghost-event-capacity-section",
          hotspots: [
            %{
              expanded: %{x: 26, y: 22, w: 64, h: 34},
              collapsed: %{x: 26, y: 20, w: 52, h: 36},
              label: "Event capacity"
            }
          ],
          public_image: "ghost:public-event-tickets",
          public_hotspots: [
            %{
              x: 66,
              y: 10,
              w: 34,
              h: 52,
              label: "Spots available and pricing headline"
            }
          ]
        },
        %{
          title: "Create ticket tiers",
          body:
            "Add one or more **tiers**. Each tier has a type — **Free**, **Paid** (fixed price), or **Donation** (attendee picks the amount) — plus an optional quantity limit and a **sales window** (start/end dates for when it can be bought).\n\nTypical setups: \"Member — free\" + \"Guest — $20\"; or an \"Early bird\" paid tier whose window closes two weeks out, followed by a regular tier. Enable **requires registration** to collect each attendee's details at checkout.\n\nOn the public event page, the sidebar shows a summary price (e.g. **From $20**), and **Get Tickets** opens a modal listing every tier you configured.",
          image: "ghost:events-tickets",
          image_scroll: "ghost-event-ticket-tiers-section",
          hotspots: [
            %{
              expanded: %{x: 28, y: 56, w: 60, h: 36},
              collapsed: %{x: 28, y: 57, w: 48, h: 36},
              label: "Ticket tiers list"
            },
            %{
              expanded: %{x: 73, y: 48, w: 14, h: 8},
              collapsed: %{x: 63, y: 48, w: 12, h: 8},
              label: "Add Ticket Tier"
            }
          ],
          public_image: "ghost:public-event-ticket-tiers",
          public_hotspots: [
            %{
              x: 10,
              y: 8,
              w: 53,
              h: 55,
              label: "Each tier name, price, and availability",
              style: :hint
            },
            %{x: 64, y: 8, w: 26, h: 55, label: "Order summary", style: :hint}
          ]
        },
        %{
          title: "Not ready to price? Use Tickets TBD",
          body:
            "If the event should be announced before pricing is final, toggle **Tickets TBD**. The event can be published showing \"tickets to be announced\", and you add real tiers when ready.\n\nThis beats delaying the announcement — members can save the date while you sort out costs.",
          image: "ghost:events-tickets",
          image_scroll: "ghost-event-ticket-tiers-section",
          public_image: "ghost:public-event-tickets-tbd",
          public_hotspots: [
            %{
              x: 8,
              y: 8,
              w: 84,
              h: 46,
              label: "Tickets coming soon on the event page",
              style: :hint
            }
          ]
        },
        %{
          title: "Monitor sales and reserve tickets",
          body:
            "Each tier shows its **sold** and **reserved** counts so you can watch uptake at a glance.\n\nNeed to hold seats — comp tickets for performers, places for the board? Use a **reservation**: pick the member and the tier, and the seats are held against capacity without payment. Reservations can be cancelled later to release the seats. Note that tiers with sold tickets can no longer be deleted, only edited."
        }
      ]
    end
  end

  defmodule EventPublish do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "events/publish"

    @impl true
    def title, do: "Publish or schedule an event"

    @impl true
    def summary,
      do:
        "Take an event live now or at a scheduled time, and handle unpublishing, cancelling, copying, and deleting."

    @impl true
    def category, do: :events

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"What exactly happens at publish?",
         "The event page goes live, the event appears in listings and feeds, members receive a notification email, ticket sales open (per each tier's sales window), and a photo-upload collection is prepared for after the event."},
        {"Does publishing email every member?",
         "Yes — publish notifications go out to members. That's why publish should be the last step, after details and tickets are final."},
        {"What's the difference between unpublish and cancel?",
         "Unpublish quietly returns the event to draft — use it for \"published too early\" mistakes. Cancel keeps the event visible but marked cancelled — use it when an announced event genuinely isn't happening, so ticket holders see the status."},
        {"When should I schedule instead of publish?",
         "When the announcement time matters — e.g. tickets go on sale Monday 09:00. Scheduling publishes automatically at the exact time, no one needs to be at a computer."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Publish button is disabled — set a title and start date first; the tooltip on the button says what's missing.",
        "Scheduled event didn't publish at the exact second — the scheduler runs every few minutes; it will go out within ~5 minutes of the chosen time.",
        "Published with a wrong date — fix the details; already-notified members keep the old email, so consider sending a correction from the Updates tab.",
        "Want to remove a cancelled event from listings — only delete if nobody bought tickets; otherwise leave it cancelled so attendees can find the status."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Pre-publish checklist",
          body:
            "Publishing requires a **title** and **start date** — but before clicking, check the rest: cover image set, summary written, location and map pin correct, overview complete, and tickets configured (or Tickets TBD enabled).\n\nPublishing emails the members, so it should be the final step, not an early one.",
          cta: %{label: "Open events", path: "/admin/events"}
        },
        %{
          title: "Publish now",
          body:
            "Click **Publish** in the editor header. The public page goes live, the event appears in listings, **members receive a notification email**, and ticket sales open according to each tier's sales window.\n\nA photo-upload collection is also created so attendees can share pictures after the event (see the Updates tab guide).",
          image: "ghost:events-edit",
          hotspots: [
            %{
              expanded: %{x: 69, y: 6, w: 10, h: 8},
              collapsed: %{x: 75, y: 7, w: 8, h: 7},
              label: "Publish"
            },
            %{
              expanded: %{x: 27, y: 7, w: 28, h: 10},
              collapsed: %{x: 26, y: 7, w: 24, h: 10},
              label: "Title and Draft badge"
            }
          ],
          public_image: "ghost:public-event-page"
        },
        %{
          title: "Or schedule the publish",
          body:
            "Click **Schedule** and pick a date and time. The event sits in the **Scheduled** state and publishes itself automatically at that moment — notifications, ticket sales and all.\n\nUse this when the announcement time is part of the plan (\"tickets drop Monday at 9\"). Scheduled events remain fully editable until they go live.",
          image: "ghost:events-edit",
          hotspots: [
            %{
              expanded: %{x: 78, y: 6, w: 13, h: 9},
              collapsed: %{x: 82, y: 6, w: 11, h: 9},
              label: "Schedule Event"
            }
          ]
        },
        %{
          title: "Unpublish or cancel",
          body:
            "**Unpublish** (on published events) quietly returns the event to draft — the public page disappears. Best for \"oops, published too soon\".\n\n**Cancel** keeps the page visible but clearly marked as cancelled — the right choice once people have seen or registered for the event, so ticket holders aren't left guessing."
        },
        %{
          title: "Copy and delete",
          body:
            "**Copy** (from the editor or the list's ⋮ menu) duplicates any event into a new draft, including its ticket tiers, agenda, and FAQs — the fastest way to set up recurring events. Always update the dates on the copy.\n\n**Delete** is available for drafts and scheduled events and is a soft delete. Published events should be cancelled rather than deleted.",
          image: "ghost:events-list",
          hotspots: [
            %{
              expanded: %{x: 85, y: 22, w: 12, h: 14},
              collapsed: %{x: 80, y: 62, w: 12, h: 18},
              label: "⋮ actions menu with options"
            }
          ]
        }
      ]
    end
  end

  defmodule EventUpdates do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "events/updates"

    @impl true
    def title, do: "Email event attendees"

    @impl true
    def summary,
      do:
        "Send updates to everyone registered, share the photo upload link, and review the event's communication history."

    @impl true
    def category, do: :events

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"Who receives an event update?",
         "Everyone with a ticket or registration for the event — the recipient count is shown before you send."},
        {"Can an update also appear on the public event page?",
         "Yes. When composing, you choose whether to email attendees, display it on the public page, or both. Public display is good for info that helps people still deciding to come."},
        {"What is the photo upload link?",
         "A shareable page where attendees upload their photos after the event — no account needed. The system also emails attendees a reminder automatically after the event ends."},
        {"Can I send an update before the event is published?",
         "No — the Updates tab works for published events, since there are no attendees before that."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Updates tab looks empty or limited — the event is still a draft; publish it first.",
        "Recipient count is zero — nobody has registered yet, so an email update would reach no one.",
        "Sent an update with an error — there's no unsend; send a short follow-up correction.",
        "Attendees can't find the photo link — re-copy it from the Updates tab and share it in an update or chat."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Open the Updates tab",
          body:
            "Edit a **published** event and switch to the **Updates** tab. This is the communication hub for the event: attendee emails, the photo upload link, and the full history of what has been sent.",
          image: "ghost:events-updates",
          hotspots: [
            %{
              expanded: %{x: 42, y: 16, w: 8, h: 8},
              collapsed: %{x: 39, y: 16, w: 6, h: 8},
              label: "Updates tab"
            }
          ]
        },
        %{
          title: "Share the photo upload link",
          body:
            "Published events get a shareable **photo upload link** where attendees can contribute their pictures without needing an account.\n\nCopy it and share it during or after the event — in an update email, the event WhatsApp group, or on a sign at the venue. Attendees also get an automatic photo reminder email after the event ends.",
          image: "ghost:events-updates",
          image_scroll: "ghost-event-photo-upload",
          hotspots: [
            %{
              expanded: %{x: 28, y: 24, w: 38, h: 24},
              collapsed: %{x: 26, y: 24, w: 42, h: 24},
              label: "Photo upload link"
            }
          ]
        },
        %{
          title: "Compose and send an update",
          body:
            "Write the update in the rich-text composer. Before sending, choose the audience: **email all attendees**, **show on the public event page**, or both.\n\nThe recipient count is shown so you know exactly how many inboxes you're reaching. Typical updates: \"parking entrance has changed\", \"bring swimwear\", \"doors now open 17:30\". Confirm to send — there is no unsend, so re-read first.",
          image: "ghost:events-updates",
          image_scroll: "ghost-event-update-composer",
          hotspots: [
            %{
              expanded: %{x: 26, y: 24, w: 42, h: 70},
              collapsed: %{x: 26, y: 24, w: 42, h: 70},
              label: "Update composer"
            }
          ],
          public_image: "ghost:public-event-updates",
          public_image_scroll: "ghost-event-updates-section",
          public_hotspots: [
            %{
              x: 1,
              y: 7,
              w: 62,
              h: 76,
              label: "Updates section on the event page",
              style: :hint
            }
          ]
        },
        %{
          title: "Review the communication timeline",
          body:
            "Below the composer, the **timeline** lists everything sent for this event: the publish notification, every update, and photo reminders — with timestamps.\n\nCheck it before sending to avoid repeating yourself, and to confirm what attendees have already been told."
        }
      ]
    end
  end

  defmodule UploadMedia do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "media/upload"

    @impl true
    def title, do: "Upload and use images"

    @impl true
    def summary,
      do:
        "Add photos to the shared media library and use them as featured images, covers, and inline pictures everywhere."

    @impl true
    def category, do: :media

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"Do I need to resize photos before uploading?",
         "No. Upload the original — the system generates optimized sizes automatically and serves the right one for each context."},
        {"Is the library shared?",
         "Yes, one library for the whole admin team. Anything you upload is available to everyone for posts, events, and newsletters — so give some thought before deleting."},
        {"What makes a good cover or featured image?",
         "Landscape orientation, bright, and with the subject near the center — covers get cropped differently on phones, cards, and emails."},
        {"Can I upload from inside the post editor?",
         "Yes — the image pickers in editors accept uploads directly, and the file lands in the same shared library."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Upload seems stuck — large originals take a moment to process; the thumbnail appears when optimization finishes.",
        "Can't find a photo you uploaded — use the search box, or scrub the timeline by year on the gallery's edge.",
        "Image looks blurry on the page — it may be a tiny original; upload a higher-resolution version.",
        "Wrong photo in a post — replacing the image in the post doesn't delete it from the library; remove it there too if it shouldn't be reused."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Open the media library",
          body:
            "Click **Media** in the sidebar. This is the single shared image library powering the whole site — post images, event covers, and newsletter photos all come from here.\n\nThe gallery shows everything newest-first, with a count at the top and a layout toggle for grid styles.",
          image: "ghost:media-gallery",
          cta: %{label: "Open media library", path: "/admin/media"}
        },
        %{
          title: "Upload photos",
          body:
            "**Drag and drop** files anywhere onto the gallery, or use the upload page. Multiple files at once is fine.\n\nUpload originals at full resolution — every image is automatically optimized into web-friendly sizes, so there's no need to pre-resize. After a club event, batch-upload the best 10–20 shots so they're ready for the recap post and newsletter.",
          image: "ghost:media-gallery",
          hotspots: [
            %{
              x: 25,
              y: 18,
              w: 72,
              h: 80,
              label: "Drop files anywhere on the gallery",
              style: :hint
            }
          ]
        },
        %{
          title: "Find images later",
          body:
            "Use the **search** box to find images, or the year scrubber along the gallery edge to jump back in time.\n\nA copy-link button on each image gives you its URL when you need it outside the site."
        },
        %{
          title: "Use images in posts, events, and newsletters",
          body:
            "You rarely need to visit the library directly — every editor opens a **picker** into it:\n\n— Posts: featured image via Post Settings, inline photos via the editor toolbar.\n— Events: cover image on the Details tab, photos inside the Overview.\n— Newsletters: cover photo and intro images.\n\nAll pickers also accept direct uploads, which land in this same shared library."
        }
      ]
    end
  end

  defmodule EventCheckIn do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "day-of/check-in"

    @impl true
    def title, do: "Event check-in desk"

    @impl true
    def summary,
      do:
        "Run the door: search attendees, check in tickets or whole orders, undo mistakes, and fly with keyboard shortcuts."

    @impl true
    def category, do: :day_of

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"Can several people run check-in at once?",
         "Yes — open the same check-in page on multiple phones or laptops. Check-ins sync live between all of them, and the counter stays accurate."},
        {"Someone bought tickets for a group — do I check each one?",
         "You can check in the whole order at once when the full group arrives together, or individual tickets if they trickle in."},
        {"I checked in the wrong person — now what?",
         "Undo it. Checked-in tickets can be reverted to pending, and the change syncs to every device immediately."},
        {"An attendee has no ticket but insists they registered — ?",
         "Search by their name and email first, then by ORD- reference from their confirmation email. If nothing is found, the host can decide — admins can also check the order records."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Check-in link missing on an event — only published (or scheduled) events have check-in; drafts don't.",
        "Search finds nothing for a known attendee — try their email or the ORD-/TKT- code from their confirmation email; names are sometimes registered differently.",
        "Counter looks wrong — it includes all tickets, including reservations; the live count syncs across devices within a second.",
        "Keyboard shortcuts not responding — click into the search box first; the shortcuts attach to it."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Open the check-in desk",
          body:
            "From the **Events** list (or the editor, or the dashboard's upcoming-events widget), choose **Check in** on a published event.\n\nThe desk shows a sticky header with the event name and a live **checked-in / total** counter, a search bar, and the attendee list grouped into pending and checked-in sections.\n\nSet this up before doors open: open the page, type a test search, and you're ready.",
          image: "ghost:check-in-desk",
          cta: %{label: "Open events", path: "/admin/events"}
        },
        %{
          title: "Search for attendees",
          body:
            "Type a **name**, **email**, **order reference** (ORD-…), or **ticket reference** (TKT-…) — the references are in every confirmation email, so an attendee can just show you their phone.\n\nResults group tickets by order, so a family of four shows as one order with four tickets.",
          image: "ghost:check-in-desk",
          hotspots: [
            %{x: 2, y: 8, w: 97, h: 9, label: "Search bar"}
          ]
        },
        %{
          title: "Check people in",
          body:
            "Click **Check in** on a single ticket, or check in the **whole order** at once when a group arrives together.\n\nEvery check-in updates the counter and syncs live to all other devices running the same desk — run two phones at a busy door and you'll never double-admit. Mistakes are reversible: undo a check-in and the ticket returns to pending everywhere.",
          image: "ghost:check-in-desk"
        },
        %{
          title: "Speed up with keyboard shortcuts",
          body:
            "With the search box focused: **↑ ↓** move through results, **Enter** checks in the highlighted ticket, and **Alt+1–3** instantly checks in the first, second, or third pending ticket on screen.\n\nThe shortcut legend is shown under the search bar. On a laptop at a busy door, type-three-letters-Enter is dramatically faster than tapping."
        },
        %{
          title: "Scanner and membership desk",
          body:
            "Two buttons in the header extend the desk:\n\n— **QR Scanner** starts a camera session that scans ticket QR codes from confirmation emails — fastest for big events (see the QR scanner guide).\n— **Membership Check-in** opens a desk for verifying member cards at the door, for member-only events.",
          cta: %{label: "QR scanner guide", path: "/admin/help/day-of/scanner"}
        }
      ]
    end
  end

  defmodule QrScanner do
    @moduledoc false
    use YscWeb.AdminHelp.Guide

    @impl true
    def slug, do: "day-of/scanner"

    @impl true
    def title, do: "QR scanner"

    @impl true
    def summary,
      do:
        "Scan ticket QR codes with your phone camera, resume interrupted sessions, and review past scan sessions."

    @impl true
    def category, do: :day_of

    @impl true
    def audience, do: [:admin, :volunteer]

    @impl true
    def faq do
      [
        {"Where do attendees get their QR code?",
         "In their ticket confirmation email (and in their wallet pass if they added one). They just show their phone screen at the door."},
        {"What session types are there?",
         "Event ticket scanning (checks in tickets for one event), event membership scanning (verifies member cards at an event), and general membership scanning (e.g. at the cabin). Pick the type when starting a session."},
        {"My phone locked mid-event — did I lose the session?",
         "No. Sessions stay open — go back to the scanner page and you'll see a Resume an Active Session card; one tap continues exactly where you left off."},
        {"A code won't scan — what now?",
         "Glare and cracked screens are the usual culprits. Ask the attendee to raise their brightness, or skip the scanner: look them up by name or ORD- code on the check-in desk instead."}
      ]
    end

    @impl true
    def troubleshooting do
      [
        "Camera doesn't start — the browser needs camera permission; check the address-bar prompt, and on iPhones use Safari.",
        "Scan rejected or shows an error — the ticket may be for a different event or already checked in; the screen explains which.",
        "Switching devices mid-event — open the scanner page on the new device and resume the open session from there.",
        "Need an audit after the event — open Past Sessions for the full list of scans with timestamps and who ran the session."
      ]
    end

    @impl true
    def steps do
      [
        %{
          title: "Open the scanner",
          body:
            "Go to **Check-in & Scan** from the events list header, or open the scanner directly. You can also launch it from any event's check-in desk — that pre-selects the event for you.\n\nThe setup screen lets you start a new session or resume one that's already open.",
          image: "ghost:scanner",
          cta: %{label: "Open scanner", path: "/admin/scanner"}
        },
        %{
          title: "Start a session",
          body:
            "Choose the session type — **event tickets** for door check-in, or **membership** for verifying member cards — and pick the event.\n\nYour browser will ask for camera permission the first time; allow it. Phones work great here: a phone on a lanyard at the door is the ideal setup.",
          image: "ghost:scanner"
        },
        %{
          title: "Scan tickets",
          body:
            "Point the camera at the attendee's QR code (from their confirmation email or wallet pass). A valid ticket checks in instantly with a clear success indicator; problems — wrong event, already checked in — are flagged on screen with the reason.\n\nEvery scan also updates the check-in desk live, so a colleague on the desk sees your scans in real time."
        },
        %{
          title: "Resume an interrupted session",
          body:
            "Phone locked, browser closed, battery swap? Sessions stay open. Return to the scanner page and tap **Resume an Active Session** — you continue with the same session and stats.\n\nYou can even resume on a different device if you switch phones mid-event."
        },
        %{
          title: "Review past sessions",
          body:
            "**Past Sessions** lists every scan session with its event, who ran it, when, and the scan log. Open a session for the detail view.\n\nUseful the morning after: confirm attendance numbers, check when the rush peaked, or audit a disputed check-in.",
          cta: %{label: "Past sessions", path: "/admin/scanner/sessions"}
        }
      ]
    end
  end
end
